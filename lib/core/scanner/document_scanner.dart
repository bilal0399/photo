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

const _scannableExtensions = {'.png', '.jpg', '.jpeg'};

/// Whether [path] is an image the scanner can process.
bool isScannable(String path) => _scannableExtensions.contains(p.extension(path).toLowerCase());

/// Longest side kept while editing, keeps decoding and warping responsive.
///
/// Pickers that can resize natively (camera / gallery) should ask for this
/// size up front: decoding a full 12MP photo in Dart is the slowest step.
const kScanWorkingSide = 2000;

/// Longest side of the produced scan.
const _maxOutputSide = 2000;

/// Longest side used while looking for the paper edges.
const _detectSide = 420;

const _jpegQuality = 85;

const fullFrameQuad = <double>[0, 0, 1, 0, 1, 1, 0, 1];

/// Working copy of a picked image plus the document corners detected in it.
///
/// [quad] holds eight normalised (0..1) values ordered
/// top-left, top-right, bottom-right, bottom-left.
class ScanPreparation {
  const ScanPreparation({
    required this.bytes,
    required this.pixels,
    required this.width,
    required this.height,
    required this.quad,
    required this.autoDetected,
    this.initial,
  });

  /// Encoded preview of the working image, for display.
  final Uint8List bytes;

  /// Raw RGB pixels of the working image. Rendering starts from these, so a
  /// filter change never has to decode the image again.
  final Uint8List pixels;
  final int width;
  final int height;
  final List<double> quad;

  /// False when edge detection was not confident and the full frame is used.
  final bool autoDetected;

  /// The scan already rendered with the detected corners, when requested
  /// through [prepareScan]'s `autoFilter` and a sheet was found.
  final ScanOutput? initial;

  ScanRequest request({
    List<double>? quad,
    ScanFilter filter = ScanFilter.auto,
    int quarterTurns = 0,
  }) =>
      ScanRequest(
        pixels: pixels,
        width: width,
        height: height,
        quad: quad ?? this.quad,
        filterIndex: filter.index,
        quarterTurns: quarterTurns,
      );
}

class ScanRequest {
  const ScanRequest({
    required this.pixels,
    required this.width,
    required this.height,
    required this.quad,
    required this.filterIndex,
    required this.quarterTurns,
  });

  /// Raw RGB pixels ([width] x [height] x 3).
  final Uint8List pixels;
  final int width;
  final int height;
  final List<double> quad;
  final int filterIndex;
  final int quarterTurns;
}

class ScanOutput {
  const ScanOutput({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

/// Result of the one-shot [scanBytes] / [scanFile].
class AutoScan {
  const AutoScan({required this.output, required this.autoDetected});

  final ScanOutput output;

  /// False when no sheet was found and only the filter was applied.
  final bool autoDetected;
}

/// Decodes [path], normalises it for editing and looks for the sheet corners.
///
/// With [autoFilter], a detected sheet is also rendered in the same background
/// pass (see [ScanPreparation.initial]), so the result can be shown at once.
Future<ScanPreparation?> prepareScan(String path, {ScanFilter? autoFilter}) =>
    compute(_prepareFile, (path, autoFilter?.index));

/// Warps the selected quad to a rectangle and applies the chosen filter.
Future<ScanOutput> renderScan(ScanRequest request) => compute(_render, request);

/// Crops (when a sheet is detected) and enhances an image in one background
/// pass, without any user interaction. Returns null when it cannot be decoded.
Future<AutoScan?> scanBytes(Uint8List bytes, {ScanFilter filter = ScanFilter.auto}) =>
    compute(_autoScan, (bytes, filter.index));

/// [scanBytes] for a file on disk.
Future<AutoScan?> scanFile(String path, {ScanFilter filter = ScanFilter.auto}) async =>
    scanBytes(await File(path).readAsBytes(), filter: filter);

const _scanDirName = 'diwan_scans';

/// Writes a finished scan to a temp file and returns its path.
Future<String> writeScanToTemp(ScanOutput output) async {
  final base = await getTemporaryDirectory();
  final dir = Directory(p.join(base.path, _scanDirName));
  await dir.create(recursive: true);
  final name = 'scan_${DateTime.now().microsecondsSinceEpoch}${output.extension}';
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(output.bytes, flush: true);
  return file.path;
}

/// Whether [path] was produced by [writeScanToTemp], i.e. is already cropped
/// and enhanced.
bool isScannerOutput(String path) => p.basename(p.dirname(path)) == _scanDirName;

// ------------------------------------------------------------ isolate entries

ScanPreparation? _prepareFile((String, int?) args) {
  final (path, autoFilter) = args;
  return _prepare(File(path).readAsBytesSync(), autoFilter);
}

AutoScan? _autoScan((Uint8List, int) args) {
  final (bytes, filterIndex) = args;
  final work = _decodeWorking(bytes);
  if (work == null) return null;
  final quad = _detectQuad(work);
  final output = _render(ScanRequest(
    pixels: work.pixels,
    width: work.width,
    height: work.height,
    quad: quad ?? fullFrameQuad,
    filterIndex: filterIndex,
    quarterTurns: 0,
  ));
  return AutoScan(output: output, autoDetected: quad != null);
}

ScanPreparation? _prepare(Uint8List raw, int? autoFilter) {
  final work = _decodeWorking(raw);
  if (work == null) return null;
  final quad = _detectQuad(work);
  final preview = _wrap(work.pixels, work.width, work.height, 3);
  final prep = ScanPreparation(
    bytes: img.encodeJpg(preview, quality: _jpegQuality),
    pixels: work.pixels,
    width: work.width,
    height: work.height,
    quad: quad ?? fullFrameQuad,
    autoDetected: quad != null,
  );
  if (autoFilter == null || quad == null) return prep;
  return ScanPreparation(
    bytes: prep.bytes,
    pixels: prep.pixels,
    width: prep.width,
    height: prep.height,
    quad: prep.quad,
    autoDetected: true,
    initial: _render(prep.request(filter: ScanFilter.values[autoFilter])),
  );
}

// ------------------------------------------------------------- pixel buffers

class _Rgb {
  const _Rgb(this.pixels, this.width, this.height);

  final Uint8List pixels;
  final int width;
  final int height;
}

img.Image _wrap(Uint8List pixels, int width, int height, int channels) => img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      bytesOffset: pixels.offsetInBytes,
      numChannels: channels,
    );

/// Decodes [raw] into upright RGB pixels no larger than [kScanWorkingSide].
_Rgb? _decodeWorking(Uint8List raw) {
  var image = img.decodeImage(raw);
  if (image == null) return null;
  final ifd = image.exif.imageIfd;
  if (ifd.hasOrientation && ifd.orientation != 1) image = img.bakeOrientation(image);
  if (image.numChannels != 3 || image.format != img.Format.uint8 || image.hasPalette) {
    image = image.convert(format: img.Format.uint8, numChannels: 3);
  }
  final pixels = image.toUint8List();
  final w = image.width;
  final h = image.height;
  final longest = math.max(w, h);
  if (longest <= kScanWorkingSide) return _Rgb(pixels, w, h);
  final scale = kScanWorkingSide / longest;
  final tw = math.max(1, (w * scale).round());
  final th = math.max(1, (h * scale).round());
  return _Rgb(_shrink(pixels, w, h, 3, tw, th), tw, th);
}

/// Area-average downscale of an interleaved buffer to [tw] x [th].
Uint8List _shrink(Uint8List src, int w, int h, int channels, int tw, int th) {
  final out = Uint8List(tw * th * channels);
  final xs = Int32List(tw + 1);
  for (var tx = 0; tx <= tw; tx++) {
    xs[tx] = tx * w ~/ tw;
  }
  final sums = Int32List(tw * channels);
  for (var ty = 0; ty < th; ty++) {
    final y0 = ty * h ~/ th;
    final y1 = math.max(y0 + 1, (ty + 1) * h ~/ th);
    sums.fillRange(0, sums.length, 0);
    for (var y = y0; y < y1; y++) {
      final row = y * w * channels;
      for (var tx = 0; tx < tw; tx++) {
        final x1 = math.max(xs[tx] + 1, xs[tx + 1]);
        final s = tx * channels;
        for (var x = xs[tx]; x < x1; x++) {
          final i = row + x * channels;
          for (var c = 0; c < channels; c++) {
            sums[s + c] += src[i + c];
          }
        }
      }
    }
    final rows = y1 - y0;
    final base = ty * tw * channels;
    for (var tx = 0; tx < tw; tx++) {
      final count = rows * (math.max(xs[tx] + 1, xs[tx + 1]) - xs[tx]);
      final s = tx * channels;
      for (var c = 0; c < channels; c++) {
        out[base + s + c] = (sums[s + c] + (count >> 1)) ~/ count;
      }
    }
  }
  return out;
}

/// Rec. 601 luma of an RGB buffer.
Uint8List _luma(Uint8List rgb, int count) {
  final out = Uint8List(count);
  for (var i = 0, j = 0; i < count; i++, j += 3) {
    out[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
  }
  return out;
}

// ------------------------------------------------------------ edge detection

/// Finds the sheet by separating it from the background, then takes the four
/// extreme points of the largest region. Returns null when the result does not
/// look like a document, so the caller can fall back to the whole frame.
List<double>? _detectQuad(_Rgb source) {
  final scale = _detectSide / math.max(source.width, source.height);
  var w = source.width;
  var h = source.height;
  var rgb = source.pixels;
  if (scale < 1) {
    final tw = math.max(16, (w * scale).round());
    final th = math.max(16, (h * scale).round());
    rgb = _shrink(rgb, w, h, 3, tw, th);
    w = tw;
    h = th;
  }
  final lum = _luma(rgb, w * h);

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
  return _isPlausible(corners) ? _inset(corners) : null;
}

/// Pulls the corners slightly towards the centre: the detected outline sits
/// right on the paper edge, and sampling there leaks a line of background.
List<double> _inset(List<double> q) {
  const keep = 0.99;
  final cx = (q[0] + q[2] + q[4] + q[6]) / 4;
  final cy = (q[1] + q[3] + q[5] + q[7]) / 4;
  return [
    for (var i = 0; i < 8; i++) i.isEven ? cx + (q[i] - cx) * keep : cy + (q[i] - cy) * keep,
  ];
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

// ---------------------------------------------------------------- rendering

ScanOutput _render(ScanRequest request) {
  final filter = ScanFilter.values[request.filterIndex];
  final w = request.width;
  final h = request.height;
  final q = request.quad;
  final corners = [for (var i = 0; i < 8; i++) q[i] * (i.isEven ? w : h)];

  double distance(int a, int b) {
    final dx = corners[a * 2] - corners[b * 2];
    final dy = corners[a * 2 + 1] - corners[b * 2 + 1];
    return math.sqrt(dx * dx + dy * dy);
  }

  // Corner order: 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left.
  var outWidth = math.max(distance(0, 1), distance(3, 2)).round();
  var outHeight = math.max(distance(0, 3), distance(1, 2)).round();
  outWidth = outWidth.clamp(32, 6000);
  outHeight = outHeight.clamp(32, 6000);
  final longest = math.max(outWidth, outHeight);
  if (longest > _maxOutputSide) {
    final factor = _maxOutputSide / longest;
    outWidth = math.max(32, (outWidth * factor).round());
    outHeight = math.max(32, (outHeight * factor).round());
  }

  var pixels = _warp(request.pixels, w, h, corners, outWidth, outHeight);
  var channels = 3;

  switch (filter) {
    case ScanFilter.original:
      break;
    case ScanFilter.auto:
      _autoLevels(pixels, _luma(pixels, outWidth * outHeight));
    case ScanFilter.grayscale:
      final lum = _luma(pixels, outWidth * outHeight);
      _autoLevels(lum, lum);
      pixels = lum;
      channels = 1;
    case ScanFilter.blackWhite:
      pixels = _adaptiveThreshold(_luma(pixels, outWidth * outHeight), outWidth, outHeight);
      channels = 1;
  }

  final turns = request.quarterTurns % 4;
  if (turns != 0) {
    pixels = _rotate(pixels, outWidth, outHeight, channels, turns);
    if (turns.isOdd) (outWidth, outHeight) = (outHeight, outWidth);
  }

  if (filter == ScanFilter.blackWhite) {
    // One channel PNG: lossless for crisp text and far smaller than RGB.
    return ScanOutput(bytes: img.encodePng(_wrap(pixels, outWidth, outHeight, 1)), extension: '.png');
  }
  if (channels == 1) pixels = _grayToRgb(pixels);
  return ScanOutput(
    bytes: img.encodeJpg(_wrap(pixels, outWidth, outHeight, 3), quality: _jpegQuality),
    extension: '.jpg',
  );
}

/// Perspective-correct warp of the source quad onto an [ow] x [oh] rectangle,
/// with bilinear sampling. [c] holds the quad in source pixel coordinates.
Uint8List _warp(Uint8List src, int w, int h, List<double> c, int ow, int oh) {
  // Projective map from the unit square to the quad (Heckbert).
  final x0 = c[0], y0 = c[1], x1 = c[2], y1 = c[3];
  final x2 = c[4], y2 = c[5], x3 = c[6], y3 = c[7];
  final sx = x0 - x1 + x2 - x3;
  final sy = y0 - y1 + y2 - y3;
  double a, b, d, e, g, hh;
  if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
    a = x1 - x0;
    b = x3 - x0;
    d = y1 - y0;
    e = y3 - y0;
    g = 0;
    hh = 0;
  } else {
    final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    final den = dx1 * dy2 - dx2 * dy1;
    g = den == 0 ? 0 : (sx * dy2 - dx2 * sy) / den;
    hh = den == 0 ? 0 : (dx1 * sy - sx * dy1) / den;
    a = x1 - x0 + g * x1;
    b = x3 - x0 + hh * x3;
    d = y1 - y0 + g * y1;
    e = y3 - y0 + hh * y3;
  }

  final out = Uint8List(ow * oh * 3);
  final maxX = w - 1;
  final maxY = h - 1;
  final stride = w * 3;
  var o = 0;
  for (var j = 0; j < oh; j++) {
    final v = (j + 0.5) / oh;
    for (var i = 0; i < ow; i++) {
      final u = (i + 0.5) / ow;
      final z = g * u + hh * v + 1;
      var fx = (a * u + b * v + x0) / z - 0.5;
      var fy = (d * u + e * v + y0) / z - 0.5;
      if (fx < 0) fx = 0;
      if (fy < 0) fy = 0;
      if (fx > maxX) fx = maxX.toDouble();
      if (fy > maxY) fy = maxY.toDouble();
      final ix = fx.toInt();
      final iy = fy.toInt();
      final tx = fx - ix;
      final ty = fy - iy;
      final nx = ix < maxX ? 3 : 0;
      final ny = iy < maxY ? stride : 0;
      final p00 = iy * stride + ix * 3;
      final p10 = p00 + nx;
      final p01 = p00 + ny;
      final p11 = p01 + nx;
      final w00 = (1 - tx) * (1 - ty);
      final w10 = tx * (1 - ty);
      final w01 = (1 - tx) * ty;
      final w11 = tx * ty;
      for (var k = 0; k < 3; k++) {
        out[o++] = (src[p00 + k] * w00 + src[p10 + k] * w10 + src[p01 + k] * w01 + src[p11 + k] * w11 + 0.5)
            .toInt();
      }
    }
  }
  return out;
}

/// Stretches the tonal range so paper turns white and ink turns dark.
/// [lum] is the luminance used for the histogram; [pixels] is updated in place.
void _autoLevels(Uint8List pixels, Uint8List lum) {
  final histogram = Int32List(256);
  for (final v in lum) {
    histogram[v]++;
  }
  final total = lum.length;
  var low = _percentile(histogram, total, 0.02);
  final high = _percentile(histogram, total, 0.985);
  if (high < 64) return; // too dark to be paper, nothing sensible to stretch
  // A mostly blank page has so little ink that even the dark percentile is
  // paper; still whiten the paper instead of leaving it grey.
  low = math.min(low, high - 128).clamp(0, 255);

  final lut = Uint8List(256);
  const strength = 0.4;
  for (var v = 0; v < 256; v++) {
    final t = ((v - low) / (high - low)).clamp(0.0, 1.0);
    final curved = t * t * (3 - 2 * t);
    lut[v] = ((t * (1 - strength) + curved * strength) * 255).round().clamp(0, 255);
  }
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = lut[pixels[i]];
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
Uint8List _adaptiveThreshold(Uint8List lum, int w, int h) {
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
      // lum < mean * 0.88, kept in integers.
      output[y * w + x] = lum[y * w + x] * count * 100 < sum * 88 ? 0 : 255;
    }
  }
  return output;
}

/// Rotates an interleaved buffer clockwise by [turns] quarter turns.
Uint8List _rotate(Uint8List src, int w, int h, int channels, int turns) {
  final out = Uint8List(src.length);
  final ow = turns.isOdd ? h : w;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (int dx, int dy) = switch (turns) {
        1 => (h - 1 - y, x),
        2 => (w - 1 - x, h - 1 - y),
        _ => (y, w - 1 - x),
      };
      final s = (y * w + x) * channels;
      final d = (dy * ow + dx) * channels;
      for (var c = 0; c < channels; c++) {
        out[d + c] = src[s + c];
      }
    }
  }
  return out;
}

Uint8List _grayToRgb(Uint8List lum) {
  final out = Uint8List(lum.length * 3);
  for (var i = 0, j = 0; i < lum.length; i++, j += 3) {
    out[j] = lum[i];
    out[j + 1] = lum[i];
    out[j + 2] = lum[i];
  }
  return out;
}
