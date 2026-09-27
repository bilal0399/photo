import 'dart:io';
import 'dart:typed_data';

import 'package:diwan_archive/core/scanner/document_scanner.dart';
import 'package:diwan_archive/features/documents/model/document.dart';
import 'package:diwan_archive/features/documents/service/bulk_rescan_service.dart';
import 'package:diwan_archive/features/documents/service/documents_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Redirects temp/documents folders into the test's own directory.
class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FakeDocumentsService implements DocumentsService {
  _FakeDocumentsService(this.files);

  /// Storage path -> bytes, or null to simulate a failed download.
  final Map<String, Uint8List?> files;
  final replaced = <String, String>{};
  final deleteFlags = <String, bool>{};

  @override
  Future<Uint8List?> attachmentBytes(String path) async => files[path];

  @override
  Future<String> replaceAttachment(Document doc, String localPath,
      {bool deleteOriginal = true}) async {
    replaced[doc.id!] = localPath;
    deleteFlags[doc.id!] = deleteOriginal;
    return '${kScannedPrefix}new${p.extension(localPath)}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Document _doc(String id, String attachment) => Document(
      id: id,
      documentCode: 'D42-$id',
      bookNumber: id,
      datetime: '2024-01-01',
      bookType: 'كتاب',
      requester: 'جهة',
      status: 'قيد المراجعة',
      direction: 'صادر',
      summary: 'ملخص',
      attachmentPath: attachment,
      approvalDate: '',
      createdAt: '2024-01-01',
    );

Uint8List _photoBytes() {
  final photo = img.Image(width: 900, height: 1200, numChannels: 3);
  img.fill(photo, color: img.ColorRgb8(45, 48, 52));
  img.fillPolygon(photo, vertices: [
    img.Point(150, 160),
    img.Point(760, 110),
    img.Point(800, 1080),
    img.Point(120, 1030),
  ], color: img.ColorRgb8(238, 238, 234));
  return img.encodeJpg(photo, quality: 92);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bulk_rescan');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('only picks image attachments that were not scanned yet', () {
    final service = BulkRescanService(_FakeDocumentsService({}));
    final docs = [
      _doc('1', 'documents/old.jpg'),
      _doc('2', 'documents/report.pdf'),
      _doc('3', '${kScannedPrefix}already.jpg'),
      _doc('4', ''),
      _doc('5', 'documents/old2.PNG'),
    ];

    expect(service.pending(docs).map((d) => d.id), ['1', '5']);
  });

  test('processes each image, backs up the original and replaces it', () async {
    final bytes = _photoBytes();
    final remote = _FakeDocumentsService({
      'documents/a.jpg': bytes,
      'documents/b.jpg': bytes,
    });
    final service = BulkRescanService(remote);
    final docs = [_doc('11', 'documents/a.jpg'), _doc('12', 'documents/b.jpg')];
    final progress = <int>[];

    final reports = await service.run(
      documents: docs,
      filter: ScanFilter.auto,
      backupOriginals: true,
      isCancelled: () => false,
      onProgress: (done, total, _) => progress.add(done),
    );

    expect(reports.map((r) => r.outcome), [RescanOutcome.cropped, RescanOutcome.cropped]);
    expect(remote.replaced.keys, ['11', '12']);
    expect(remote.deleteFlags.values, everyElement(isTrue));
    expect(progress.last, 2);

    // The uploaded file is a real, cropped image.
    final processed = img.decodeImage(File(remote.replaced['11']!).readAsBytesSync())!;
    expect(processed.width, lessThan(900));

    // Originals are kept on disk before the cloud copy is dropped.
    final backups = (await service.backupDirectory()).listSync().map((f) => p.basename(f.path));
    expect(backups, containsAll(['11_a.jpg', '12_b.jpg']));
  });

  test('a failed download is reported and never replaces the attachment', () async {
    final remote = _FakeDocumentsService({'documents/gone.jpg': null});
    final service = BulkRescanService(remote);

    final reports = await service.run(
      documents: [_doc('21', 'documents/gone.jpg')],
      filter: ScanFilter.auto,
      backupOriginals: false,
      isCancelled: () => false,
      onProgress: (_, _, _) {},
    );

    expect(reports.single.outcome, RescanOutcome.failed);
    expect(reports.single.message, 'تعذّر تحميل الصورة');
    expect(remote.replaced, isEmpty);
  });

  test('stops when cancelled', () async {
    final remote = _FakeDocumentsService({
      'documents/a.jpg': _photoBytes(),
      'documents/b.jpg': _photoBytes(),
    });
    final service = BulkRescanService(remote);

    final reports = await service.run(
      documents: [_doc('31', 'documents/a.jpg'), _doc('32', 'documents/b.jpg')],
      filter: ScanFilter.grayscale,
      backupOriginals: false,
      isCancelled: () => remote.replaced.isNotEmpty,
      onProgress: (_, _, _) {},
    );

    expect(reports, hasLength(1));
    expect(remote.replaced.keys, ['31']);
  });
}
