import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'scan_preview_page.dart';

const _scannableExtensions = {'.png', '.jpg', '.jpeg'};

bool isScannable(String path) => _scannableExtensions.contains(p.extension(path).toLowerCase());

/// Sends a freshly picked image through the scanner preview (edge detection,
/// crop adjustment and enhancement) before it is attached.
///
/// Returns the processed file path, the original path for non-image files, or
/// null when the user cancels the preview.
Future<String?> runScanFlow(
  BuildContext context,
  String sourcePath, {
  String confirmLabel = 'إدراج الصورة',
}) {
  if (!isScannable(sourcePath)) return Future.value(sourcePath);
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => ScanPreviewPage(sourcePath: sourcePath, confirmLabel: confirmLabel),
      fullscreenDialog: true,
    ),
  );
}
