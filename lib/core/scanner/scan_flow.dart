import 'package:flutter/material.dart';

import 'document_scanner.dart';
import 'scan_preview_page.dart';

export 'document_scanner.dart' show isScannable, kScanWorkingSide;

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
