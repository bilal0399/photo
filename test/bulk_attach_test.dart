import 'dart:io';
import 'dart:typed_data';

import 'package:diwan_archive/core/scanner/document_scanner.dart';
import 'package:diwan_archive/features/documents/model/document.dart';
import 'package:diwan_archive/features/documents/service/bulk_attach_service.dart';
import 'package:diwan_archive/features/documents/service/documents_service.dart';
import 'package:diwan_archive/features/documents/view/bulk_attach_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

class _FakeDocumentsService implements DocumentsService {
  _FakeDocumentsService([this.documents = const []]);

  final List<Document> documents;

  @override
  Future<List<Document>> all() async => documents;

  /// Document id -> bytes that were uploaded for it.
  final uploaded = <String, Uint8List>{};
  final uploadedNames = <String, String>{};

  @override
  Future<String> replaceAttachment(Document doc, String localPath, {bool deleteOriginal = true}) async {
    uploaded[doc.id!] = await File(localPath).readAsBytes();
    uploadedNames[doc.id!] = p.basename(localPath);
    return '${kScannedPrefix}x${p.extension(localPath)}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Document _doc(String id, String number, {String date = '2025-03-01', String direction = kOutgoing, String attachment = ''}) =>
    Document(
      id: id,
      documentCode: 'D-$id',
      bookNumber: number,
      datetime: date,
      bookType: 'كتاب',
      requester: 'جهة',
      status: 'قيد المراجعة',
      direction: direction,
      summary: 'ملخص',
      attachmentPath: attachment,
      approvalDate: '',
      createdAt: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('numberFromName', () {
    test('reads plain, zero padded and Arabic-Indic numbers', () {
      expect(BulkAttachService.numberFromName('/x/7.jpg'), '7');
      expect(BulkAttachService.numberFromName('007.PNG'), '7');
      expect(BulkAttachService.numberFromName('٤٢.jpg'), '42');
      expect(BulkAttachService.numberFromName(' 15 .pdf'), '15');
    });

    test('rejects names that are not a number', () {
      expect(BulkAttachService.numberFromName('scan 7.jpg'), isNull);
      expect(BulkAttachService.numberFromName('IMG_2031.jpg'), isNull);
      expect(BulkAttachService.numberFromName('.jpg'), isNull);
    });
  });

  group('plan', () {
    final service = BulkAttachService(_FakeDocumentsService());
    final docs = [
      _doc('a', '7'),
      _doc('b', '8', attachment: 'documents/old.jpg'),
      _doc('c', '9', date: '2024-05-01'),
      _doc('d', '9', date: '2025-05-01'),
      _doc('e', '10', direction: kIncoming),
      _doc('f', '10', direction: kOutgoing),
    ];

    test('matches each file to its document and explains the rest', () {
      final items = service.plan([
        '7.jpg',
        '8.jpg',
        '9.jpg',
        '11.jpg',
        'photo.jpg',
        '7.docx',
        '٧.png',
      ], docs);

      expect(items.map((i) => i.status), [
        AttachStatus.ready,
        AttachStatus.hasAttachment,
        AttachStatus.ambiguous,
        AttachStatus.notFound,
        AttachStatus.badName,
        AttachStatus.unsupported,
        AttachStatus.duplicateFile,
      ]);
      expect(items.first.document?.id, 'a');
      expect(items[2].candidates.map((d) => d.id), ['c', 'd']);
    });

    test('year and direction settle repeated numbers', () {
      expect(service.plan(['9.jpg'], docs, year: '2024').single.document?.id, 'c');
      expect(service.plan(['10.jpg'], docs, direction: kIncoming).single.document?.id, 'e');
    });

    test('existing attachments are only replaced when asked', () {
      final item = service.plan(['8.jpg'], docs, replaceExisting: true).single;
      expect(item.status, AttachStatus.replaces);
      expect(item.status.willUpload, isTrue);
    });
  });

  group('run', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bulk_attach');
      PathProviderPlatform.instance = _FakePathProvider(temp.path);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    File photo(String name) {
      final image = img.Image(width: 900, height: 1200, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(45, 48, 52));
      img.fillPolygon(image, vertices: [
        img.Point(150, 160),
        img.Point(760, 110),
        img.Point(800, 1080),
        img.Point(120, 1030),
      ], color: img.ColorRgb8(238, 238, 234));
      return File(p.join(temp.path, name))..writeAsBytesSync(img.encodeJpg(image));
    }

    test('crops and enhances images, uploads PDFs as they are, skips the rest', () async {
      final remote = _FakeDocumentsService();
      final service = BulkAttachService(remote);
      final pdf = File(p.join(temp.path, '8.pdf'))..writeAsBytesSync([37, 80, 68, 70]);
      final items = service.plan(
        [photo('7.jpg').path, pdf.path, photo('99.jpg').path],
        [_doc('a', '7'), _doc('b', '8')],
      );

      final progress = <int>[];
      final reports = await service.run(
        items: items,
        enhance: true,
        filter: ScanFilter.auto,
        onProgress: (done, _, _) => progress.add(done),
        isCancelled: () => false,
      );

      expect(reports.map((r) => r.outcome), [AttachOutcome.cropped, AttachOutcome.attached]);
      expect(remote.uploaded.keys.toSet(), {'a', 'b'});
      final cropped = img.decodeImage(remote.uploaded['a']!)!;
      expect(cropped.width, lessThan(900));
      expect(remote.uploaded['b'], [37, 80, 68, 70]);
      expect(progress.last, 2);
    });

    test('without enhancement the original image is uploaded', () async {
      final remote = _FakeDocumentsService();
      final service = BulkAttachService(remote);
      final file = photo('7.jpg');

      final reports = await service.run(
        items: service.plan([file.path], [_doc('a', '7')]),
        enhance: false,
        filter: ScanFilter.auto,
        onProgress: (_, _, _) {},
        isCancelled: () => false,
      );

      expect(reports.single.outcome, AttachOutcome.attached);
      expect(remote.uploaded['a'], file.readAsBytesSync());
    });
  });

  testWidgets('the page shows how many documents still lack an attachment', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final remote = _FakeDocumentsService([_doc('a', '1'), _doc('b', '2', attachment: 'x.jpg')]);

    await tester.pumpWidget(ProviderScope(
      overrides: [documentsServiceProvider.overrideWithValue(remote)],
      child: const MaterialApp(home: BulkAttachPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('طلبات بدون مرفق: 1 من أصل 2'), findsOneWidget);
    expect(find.text('لا توجد ملفات جاهزة'), findsOneWidget);
  });
}
