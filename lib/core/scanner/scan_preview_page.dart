import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'document_scanner.dart';

/// Preview step shown after picking an image and before it is attached.
///
/// Step 1 lets the user fine tune the four document corners detected
/// automatically; step 2 shows the rectified result with the scanner filters.
/// Pops with the path of the processed file, or null when cancelled.
class ScanPreviewPage extends StatefulWidget {
  const ScanPreviewPage({
    super.key,
    required this.sourcePath,
    this.confirmLabel = 'إدراج الصورة',
  });

  final String sourcePath;

  /// Label of the primary button on the result step.
  final String confirmLabel;

  @override
  State<ScanPreviewPage> createState() => _ScanPreviewPageState();
}

class _ScanPreviewPageState extends State<ScanPreviewPage> {
  static const _handleRadius = 14.0;
  static const _grabRadius = 44.0;

  ScanPreparation? _prep;
  String? _error;

  List<Offset> _corners = const [];
  List<Offset> _detected = const [];
  int _dragIndex = -1;
  Offset _dragPointer = Offset.zero;

  bool _cropping = true;
  bool _busy = false;
  ScanFilter _filter = ScanFilter.auto;
  int _quarterTurns = 0;
  Uint8List? _result;
  ScanOutput? _output;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prep = await prepareScan(widget.sourcePath);
      if (!mounted) return;
      if (prep == null) {
        setState(() => _error = 'تعذر قراءة الصورة');
        return;
      }
      setState(() {
        _prep = prep;
        _detected = _toOffsets(prep.quad);
        _corners = List.of(_detected);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تجهيز الصورة: $e');
    }
  }

  List<Offset> _toOffsets(List<double> quad) =>
      [for (var i = 0; i < 4; i++) Offset(quad[i * 2], quad[i * 2 + 1])];

  List<double> get _quadValues =>
      [for (final c in _corners) ...[c.dx, c.dy]];

  Future<void> _render() async {
    final prep = _prep;
    if (prep == null) return;
    setState(() => _busy = true);
    try {
      final output = await renderScan(ScanRequest(
        bytes: prep.bytes,
        quad: _quadValues,
        filterIndex: _filter.index,
        quarterTurns: _quarterTurns,
      ));
      if (!mounted) return;
      setState(() {
        _output = output;
        _result = output.bytes;
        _cropping = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر المعالجة: $e')));
    }
  }

  Future<void> _insert() async {
    final prep = _prep;
    if (prep == null) return;
    setState(() => _busy = true);
    try {
      // The preview already holds the current settings; only render if missing.
      final output = _output ??
          await renderScan(ScanRequest(
            bytes: prep.bytes,
            quad: _quadValues,
            filterIndex: _filter.index,
            quarterTurns: _quarterTurns,
          ));
      final path = await writeScanToTemp(output);
      if (mounted) Navigator.of(context).pop(path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_cropping ? 'تحديد حواف الورقة' : 'معاينة قبل الإدراج'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'إلغاء',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
          : _prep == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(child: _cropping ? _cropStage() : _resultStage()),
                        _controls(),
                      ],
                    ),
                    if (_busy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
    );
  }

  // ---------------------------------------------------------------- crop step

  Widget _cropStage() {
    final prep = _prep!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rect = _fittedRect(
            Size(prep.width.toDouble(), prep.height.toDouble()),
            constraints.biggest,
          );
          final points = [for (final c in _corners) rect.topLeft + Offset(c.dx * rect.width, c.dy * rect.height)];

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => _onDragStart(details.localPosition, points),
            onPanUpdate: (details) => _onDragUpdate(details.localPosition, rect),
            onPanEnd: (_) => setState(() => _dragIndex = -1),
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Image.memory(prep.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _QuadPainter(
                      points: points,
                      area: rect,
                      color: Theme.of(context).colorScheme.primary,
                      activeIndex: _dragIndex,
                      handleRadius: _handleRadius,
                    ),
                  ),
                ),
                if (_dragIndex >= 0) _magnifier(points[_dragIndex], constraints.biggest),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Loupe pinned to the opposite side of the screen from the dragged corner.
  Widget _magnifier(Offset point, Size area) {
    const size = Size(120, 120);
    final onLeft = point.dx < area.width / 2;
    return Positioned(
      top: 0,
      left: onLeft ? area.width - size.width : 0,
      child: RawMagnifier(
        size: size,
        focalPointOffset: Offset(
          point.dx - (onLeft ? area.width - size.width / 2 : size.width / 2),
          point.dy - size.height / 2,
        ),
        magnificationScale: 2,
        decoration: MagnifierDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white70, width: 2),
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }

  void _onDragStart(Offset position, List<Offset> points) {
    var nearest = -1;
    var best = _grabRadius;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - position).distance;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    setState(() {
      _dragIndex = nearest;
      _dragPointer = position;
    });
  }

  void _onDragUpdate(Offset position, Rect rect) {
    if (_dragIndex < 0) return;
    final delta = position - _dragPointer;
    _dragPointer = position;
    final current = _corners[_dragIndex];
    final moved = Offset(
      (current.dx + delta.dx / rect.width).clamp(0.0, 1.0),
      (current.dy + delta.dy / rect.height).clamp(0.0, 1.0),
    );
    setState(() {
      final next = List.of(_corners);
      next[_dragIndex] = moved;
      _corners = next;
    });
  }

  Rect _fittedRect(Size image, Size box) {
    final scale = math.min(box.width / image.width, box.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  // -------------------------------------------------------------- result step

  Widget _resultStage() {
    final bytes = _result;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: bytes == null
            ? const CircularProgressIndicator()
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 18)],
                ),
                child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
              ),
      ),
    );
  }

  // ----------------------------------------------------------------- controls

  Widget _controls() {
    final prep = _prep!;
    return Container(
      width: double.infinity,
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_cropping) ...[
              Text(
                prep.autoDetected
                    ? 'تم كشف حواف الورقة تلقائياً، اسحب النقاط لضبط الاقتصاص'
                    : 'لم يتم كشف الحواف بوضوح، اسحب النقاط لتحديد الورقة',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  _chipButton(
                    icon: Icons.crop_free,
                    label: 'الصورة كاملة',
                    onTap: () => setState(() => _corners = _toOffsets(fullFrameQuad)),
                  ),
                  _chipButton(
                    icon: Icons.auto_fix_high_outlined,
                    label: 'الحواف المكتشفة',
                    onTap: () => setState(() => _corners = List.of(_detected)),
                  ),
                ],
              ),
            ] else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in ScanFilter.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(filter.label),
                          selected: _filter == filter,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(() => _filter = filter);
                                  _render();
                                },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _chipButton(
                    icon: Icons.rotate_left,
                    label: 'تدوير يسار',
                    onTap: _busy
                        ? null
                        : () {
                            setState(() => _quarterTurns = (_quarterTurns + 3) % 4);
                            _render();
                          },
                  ),
                  const SizedBox(width: 8),
                  _chipButton(
                    icon: Icons.rotate_right,
                    label: 'تدوير يمين',
                    onTap: _busy
                        ? null
                        : () {
                            setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
                            _render();
                          },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_cropping) {
                              Navigator.of(context).pop();
                            } else {
                              setState(() {
                                _cropping = true;
                                _output = null;
                              });
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: Icon(_cropping ? Icons.close : Icons.crop),
                    label: Text(_cropping ? 'إلغاء' : 'تعديل الاقتصاص'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : (_cropping ? _render : _insert),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: Icon(_cropping ? Icons.auto_awesome : Icons.check),
                    label: Text(_cropping ? 'معالجة ومعاينة' : widget.confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipButton({required IconData icon, required String label, VoidCallback? onTap}) =>
      TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.points,
    required this.area,
    required this.color,
    required this.activeIndex,
    required this.handleRadius,
  });

  final List<Offset> points;
  final Rect area;
  final Color color;
  final int activeIndex;
  final double handleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final quad = Path()..addPolygon(points, true);

    // Dim everything outside the selection.
    final shade = Path.combine(PathOperation.difference, Path()..addRect(area), quad);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawPath(
      quad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );

    for (var i = 0; i < points.length; i++) {
      final active = i == activeIndex;
      final radius = active ? handleRadius + 4 : handleRadius;
      canvas.drawCircle(points[i], radius, Paint()..color = Colors.white.withValues(alpha: 0.9));
      canvas.drawCircle(
        points[i],
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.points != points || old.activeIndex != activeIndex || old.area != area;
}
