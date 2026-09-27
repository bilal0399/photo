import 'dart:io';

import 'package:diwan_archive/core/scanner/document_scanner.dart';
import 'package:diwan_archive/core/scanner/scan_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Builds a fake photo: a tilted white sheet with text lines on a dark desk.
File _fakePhoto(Directory dir, List<img.Point> sheet) {
  final photo = img.Image(width: 900, height: 1200, numChannels: 3);
  img.fill(photo, color: img.ColorRgb8(45, 48, 52));
  img.fillPolygon(photo, vertices: sheet, color: img.ColorRgb8(238, 238, 234));
  for (var i = 0; i < 12; i++) {
    final y = 220 + i * 60;
    img.fillRect(photo, x1: 220, y1: y, x2: 640, y2: y + 12, color: img.ColorRgb8(30, 30, 30));
  }
  final file = File('${dir.path}/photo.jpg')..writeAsBytesSync(img.encodeJpg(photo, quality: 92));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('scan_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('detects the corners of a tilted sheet', () async {
    final sheet = [
      img.Point(150, 160), // top-left
      img.Point(760, 110), // top-right
      img.Point(800, 1080), // bottom-right
      img.Point(120, 1030), // bottom-left
    ];
    final prep = await prepareScan(_fakePhoto(temp, sheet).path);

    expect(prep, isNotNull);
    expect(prep!.autoDetected, isTrue);
    for (var i = 0; i < 4; i++) {
      expect((prep.quad[i * 2] * 900 - sheet[i].x).abs(), lessThan(25), reason: 'x of corner $i');
      expect((prep.quad[i * 2 + 1] * 1200 - sheet[i].y).abs(), lessThan(25), reason: 'y of corner $i');
    }
  });

  test('falls back to the full frame when no sheet stands out', () async {
    final flat = img.Image(width: 600, height: 800, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(210, 210, 210));
    final file = File('${temp.path}/flat.jpg')..writeAsBytesSync(img.encodeJpg(flat));

    final prep = await prepareScan(file.path);

    expect(prep, isNotNull);
    expect(prep!.autoDetected, isFalse);
    expect(prep.quad, fullFrameQuad);
  });

  test('rectifies the selection and applies the black and white filter', () async {
    final sheet = [
      img.Point(150, 160),
      img.Point(760, 110),
      img.Point(800, 1080),
      img.Point(120, 1030),
    ];
    final prep = await prepareScan(_fakePhoto(temp, sheet).path);

    final output = await renderScan(ScanRequest(
      bytes: prep!.bytes,
      quad: prep.quad,
      filterIndex: ScanFilter.blackWhite.index,
      quarterTurns: 1,
    ));

    expect(output.extension, '.png');
    final result = img.decodeImage(output.bytes)!;
    // Rotated a quarter turn, so the portrait sheet comes out landscape.
    expect(result.width, greaterThan(result.height));
    // The desk background must be gone: corners of the scan are paper white.
    expect(result.getPixel(4, 4).r, greaterThan(200));
    // Thresholding keeps only black and white.
    final values = {for (final px in result) px.r.toInt()};
    expect(values, {0, 255});
  });

  testWidgets('preview page goes from corner adjustment to the scanned result', (tester) async {
    final photo = _fakePhoto(temp, [
      img.Point(150, 160),
      img.Point(760, 110),
      img.Point(800, 1080),
      img.Point(120, 1030),
    ]);

    // The scanner runs on a background isolate, so the test needs real async.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        home: ScanPreviewPage(sourcePath: photo.path),
      ));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();

    expect(find.text('تحديد حواف الورقة'), findsOneWidget);
    expect(find.text('تم كشف حواف الورقة تلقائياً، اسحب النقاط لضبط الاقتصاص'), findsOneWidget);

    // Grab the top-left handle where it is drawn on screen and move it inwards.
    final prep = (await tester.runAsync(() => prepareScan(photo.path)))!;
    final shown = tester.getRect(find.byType(Image));
    final handle = shown.topLeft + Offset(prep.quad[0] * shown.width, prep.quad[1] * shown.height);
    await tester.dragFrom(handle, const Offset(40, 40));
    await tester.pump();

    await tester.tap(find.text('معالجة ومعاينة'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();

    expect(find.text('معاينة قبل الإدراج'), findsOneWidget);
    expect(find.text('إدراج الصورة'), findsOneWidget);
    expect(find.text(ScanFilter.blackWhite.label), findsOneWidget);
  });
}
