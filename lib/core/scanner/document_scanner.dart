import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Scanner-style post processing applied to a picked image.
enum ScanFilter {
  original('الأصلية'),
  auto('تحسين تلقائي'),
  grayscale('رمادي'),
  blackWhite('أبيض وأسود');

  const ScanFilter(this.label);

  final String label;
}

/// Working copy of a picked image plus the document corners detected in it.
///
/// [quad] holds eight normalised (0..1) values ordered
/// top-left, top-right, bottom-right, bottom-left.
class ScanPreparation {
  const ScanPreparation({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quad,
    required this.autoDetected,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final List<double> quad;

  /// False when edge detection was not confident and the full frame is used.
  final bool autoDetected;
}

class ScanRequest {
  const ScanRequest({
    required this.bytes,
    required this.quad,
    required this.filterIndex,
    required this.quarterTurns,
  });

  final Uint8List bytes;
  final List<double> quad;
  final int filterIndex;
  final int quarterTurns;
}

class ScanOutput {
  const ScanOutput({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

/// Longest side kept while editing, keeps decoding and warping responsive.
const _maxWorkingSide = 2000;

/// Longest side of the produced scan.
const _maxOutputSide = 2000;

/// Longest side used while looking for the paper edges.
const _detectSide = 420;

const fullFrameQuad = <double>[0, 0, 1, 0, 1, 1, 0, 1];

/// Decodes [path], normalises it for editing and looks for the sheet corners.
Future<ScanPreparation?> prepareScan(String path) => compute(_prepare, path);

/// Warps the selected quad to a rectangle and applies the chosen filter.
Future<ScanOutput> renderScan(ScanRequest request) => compute(_render, request);

Future<String> writeScanToTemp(ScanOutput output) async {
  final dir = await getTemporaryDirectory();
  final name = 'scan_${DateTime.now().millisecondsSinceEpoch}${output.extension}';
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(output.bytes, flush: true);
  return file.path;
}

ScanPreparation? _prepare(String path) {
  final raw = File(path).readAsBytesSync();
  var image = img.decodeImage(raw);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  final longest = math.max(image.width, image.height);
  if (longest > _maxWorkingSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxWorkingSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: _maxWorkingSide, interpolation: img.Interpolation.average);
  }
  final quad = _detectQuad(image);
  return ScanPreparation(
    bytes: img.encodeJpg(image, quality: 92),
    width: image.width,
    height: image.height,
    quad: quad ?? fullFrameQuad,
    autoDetected: quad != null,
  );
}

/// Finds the sheet by separating it from the background, then takes the four
/// extreme points of the largest region. Returns null when the result does not
/// look like a document, so the caller can fall back to the whole frame.
List<double>? _detectQuad(img.Image source) {
  final scale = _detectSide / math.max(source.width, source.height);
  final small = scale >= 1
      ? source.clone()
      : img.copyResize(
          source,
          width: math.max(16, (source.width * scale).round()),
          interpolation: img.Interpolation.average,
        );
  img.grayscale(small);

  final w = small.width;
  final h = small.height;
  final lum = Uint8List(w * h);
  var i = 0;
  for (final px in small) {
    if (i >= lum.length) break;
    lum[i++] = px.r.toInt().clamp(0, 255);
  }

  final band = math.max(2, (math.min(w, h) * 0.04).round());
  final border = <int>[];
  final centre = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = lum[y * w + x];
      if (x < band || y < band || x >= w - band || y >= h - band) {
        border.add(v);
      } else if (x > w * 0.3 && x < w * 0.7 && y > h * 0.3 && y < h * 0.7) {
        centre.add(v);
      }
    }
  }
  if (border.isEmpty || centre.isEmpty) return null;
  border.sort();
  centre.sort();
  final background = border[border.length ~/ 2];
  final foreground = centre[centre.length ~/ 2];
  final contrast = (foreground - background).abs();
  if (contrast < 20) return null;

  final brighter = foreground > background;
  final threshold = math.max(18, (contrast * 0.35).round());
  final mask = Uint8List(w * h);
  for (var k = 0; k < mask.length; k++) {
    final v = lum[k];
    final isDoc = brighter ? v > background + threshold : v < background - threshold;
    mask[k] = isDoc ? 1 : 0;
  }

  final region = _largestRegion(mask, w, h);
  if (region == null) return null;

  // Extreme points of a rotated rectangle: corners minimise/maximise x+y, x-y.
  var minSum = 1 << 30;
  var maxSum = -(1 << 30);
  var minDiff = 1 << 30;
  var maxDiff = -(1 << 30);
  var tlx = 0, tly = 0, trx = 0, trY = 0, brx = 0, bry = 0, blx = 0, bly = 0;
  for (final index in region) {
    final x = index % w;
    final y = index ~/ w;
    final sum = x + y;
    final diff = x - y;
    if (sum < minSum) {
      minSum = sum;
      tlx = x;
      tly = y;
    }
    if (sum > maxSum) {
      maxSum = sum;
      brx = x;
      bry = y;
    }
    if (diff > maxDiff) {
      maxDiff = diff;
      trx = x;
      trY = y;
    }
    if (diff < minDiff) {
      minDiff = diff;
      blx = x;
      bly = y;
    }
  }

  final corners = <double>[
    tlx / w, tly / h,
    trx / w, trY / h,
    brx / w, bry / h,
    blx / w, bly / h,
  ];
  return _isPlausible(corners) ? corners : null;
}

/// Flood fills the mask and returns the pixel indices of the biggest region.
List<int>? _largestRegion(Uint8List mask, int w, int h) {
  final visited = Uint8List(mask.length);
  final queue = Int32List(mask.length);
  List<int>? best;
  final minArea = (mask.length * 0.12).round();

  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || visited[start] == 1) continue;
    var head = 0;
    var tail = 0;
    queue[tail++] = start;
    visited[start] = 1;
    final pixels = <int>[];
    while (head < tail) {
      final index = queue[head++];
      pixels.add(index);
      final x = index % w;
      final y = index ~/ w;
      if (x > 0) {
        final n = index - 1;
        if (mask[n] == 1 && visited[n] == 0) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (x < w - 1) {
        final n = index + 1;
        if (mask[n] == 1 && visited[n] == 0) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (y > 0) {
        final n = index - w;
        if (mask[n] == 1 && visited[n] == 0) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (y < h - 1) {
        final n = index + w;
        if (mask[n] == 1 && visited[n] == 0) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
    }
    if (pixels.length >= minArea && (best == null || pixels.length > best.length)) {
      best = pixels;
    }
  }
  return best;
}

/// Rejects detections that are too small, too thin or nearly degenerate.
bool _isPlausible(List<double> q) {
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    final x1 = q[i * 2];
    final y1 = q[i * 2 + 1];
    final x2 = q[(i + 1) % 4 * 2];
    final y2 = q[(i + 1) % 4 * 2 + 1];
    area += x1 * y2 - x2 * y1;
  }
  area = area.abs() / 2;
  if (area < 0.15) return false;

  for (var i = 0; i < 4; i++) {
    final dx = q[(i + 1) % 4 * 2] - q[i * 2];
    final dy = q[(i + 1) % 4 * 2 + 1] - q[i * 2 + 1];
    if (math.sqrt(dx * dx + dy * dy) < 0.12) return false;
  }
  return true;
}

ScanOutput _render(ScanRequest request) {
  final source = img.decodeImage(request.bytes);
  if (source == null) {
    return ScanOutput(bytes: request.bytes, extension: '.jpg');
  }
  final filter = ScanFilter.values[request.filterIndex];
  final w = source.width.toDouble();
  final h = source.height.toDouble();
  final q = request.quad;
  final topLeft = img.Point(q[0] * w, q[1] * h);
  final topRight = img.Point(q[2] * w, q[3] * h);
  final bottomRight = img.Point(q[4] * w, q[5] * h);
  final bottomLeft = img.Point(q[6] * w, q[7] * h);

  double distance(img.Point a, img.Point b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  var outWidth = math.max(distance(topLeft, topRight), distance(bottomLeft, bottomRight)).round();
  var outHeight = math.max(distance(topLeft, bottomLeft), distance(topRight, bottomRight)).round();
  outWidth = outWidth.clamp(32, 6000);
  outHeight = outHeight.clamp(32, 6000);
  final longest = math.max(outWidth, outHeight);
  if (longest > _maxOutputSide) {
    final factor = _maxOutputSide / longest;
    outWidth = math.max(32, (outWidth * factor).round());
    outHeight = math.max(32, (outHeight * factor).round());
  }

  var result = img.copyRectify(
    source,
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
    interpolation: img.Interpolation.cubic,
    toImage: img.Image(width: outWidth, height: outHeight, numChannels: 3),
  );

  switch (filter) {
    case ScanFilter.original:
      break;
    case ScanFilter.auto:
      _autoLevels(result, toGrayscale: false);
    case ScanFilter.grayscale:
      _autoLevels(result, toGrayscale: true);
    case ScanFilter.blackWhite:
      _adaptiveThreshold(result);
  }

  if (request.quarterTurns % 4 != 0) {
    result = img.copyRotate(result, angle: (request.quarterTurns % 4) * 90);
  }

  return filter == ScanFilter.blackWhite
      ? ScanOutput(bytes: img.encodePng(result), extension: '.png')
      : ScanOutput(bytes: img.encodeJpg(result, quality: 92), extension: '.jpg');
}

int _luminance(img.Pixel p) => (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);

/// Stretches the tonal range so paper turns white and ink turns dark.
void _autoLevels(img.Image image, {required bool toGrayscale}) {
  if (toGrayscale) img.grayscale(image);

  final histogram = Int32List(256);
  for (final px in image) {
    histogram[_luminance(px)]++;
  }
  final total = image.width * image.height;
  final low = _percentile(histogram, total, 0.02);
  final high = _percentile(histogram, total, 0.985);
  if (high - low < 24) return;

  final lut = Uint8List(256);
  const strength = 0.4;
  for (var v = 0; v < 256; v++) {
    final t = ((v - low) / (high - low)).clamp(0.0, 1.0);
    final curved = t * t * (3 - 2 * t);
    lut[v] = ((t * (1 - strength) + curved * strength) * 255).round().clamp(0, 255);
  }
  for (final px in image) {
    px
      ..r = lut[px.r.toInt().clamp(0, 255)]
      ..g = lut[px.g.toInt().clamp(0, 255)]
      ..b = lut[px.b.toInt().clamp(0, 255)];
  }
}

int _percentile(Int32List histogram, int total, double fraction) {
  final target = (total * fraction).round();
  var seen = 0;
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen >= target) return v;
  }
  return 255;
}

/// Bradley adaptive threshold: keeps text crisp under uneven lighting.
void _adaptiveThreshold(img.Image image) {
  img.grayscale(image);
  final w = image.width;
  final h = image.height;
  final lum = Uint8List(w * h);
  var i = 0;
  for (final px in image) {
    if (i >= lum.length) break;
    lum[i++] = px.r.toInt().clamp(0, 255);
  }

  final integral = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += lum[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + rowSum;
    }
  }

  final radius = math.max(6, (math.min(w, h) / 28).round());
  final output = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y1 = math.max(0, y - radius);
    final y2 = math.min(h - 1, y + radius);
    for (var x = 0; x < w; x++) {
      final x1 = math.max(0, x - radius);
      final x2 = math.min(w - 1, x + radius);
      final count = (x2 - x1 + 1) * (y2 - y1 + 1);
      final sum = integral[(y2 + 1) * (w + 1) + x2 + 1] -
          integral[y1 * (w + 1) + x2 + 1] -
          integral[(y2 + 1) * (w + 1) + x1] +
          integral[y1 * (w + 1) + x1];
      final mean = sum / count;
      output[y * w + x] = lum[y * w + x] < mean * 0.88 ? 0 : 255;
    }
  }

  i = 0;
  for (final px in image) {
    if (i >= output.length) break;
    final v = output[i++];
    px
      ..r = v
      ..g = v
      ..b = v;
  }
}
