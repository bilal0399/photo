import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'scan_flow.dart';

/// Runs an already stored image through the scanner preview.
///
/// Downloads the attachment to a temp file, opens the crop/enhance preview and
/// returns the processed local file, ready to be uploaded as the new
/// attachment. Returns null when the download fails or the user cancels.
Future<String?> rescanStoredImage(
  BuildContext context, {
  required String storagePath,
  required Future<Uint8List?> Function() download,
}) async {
  if (!isScannable(storagePath)) {
    _snack(context, 'المرفق ليس صورة، لا يمكن معالجته كسكانر');
    return null;
  }

  final bytes = await withBlockingProgress(context, 'جارٍ تحميل الصورة...', download);
  if (!context.mounted) return null;
  if (bytes == null) {
    _snack(context, 'تعذّر تحميل الصورة. تحقّق من الاتصال.');
    return null;
  }

  final dir = await getTemporaryDirectory();
  final name = 'rescan_${DateTime.now().millisecondsSinceEpoch}'
      '${p.extension(storagePath).toLowerCase()}';
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  if (!context.mounted) return null;

  return runScanFlow(context, file.path, confirmLabel: 'استبدال الصورة');
}

/// Shows a modal spinner while [work] runs, so slow uploads/downloads are
/// visible and cannot be interrupted by a second tap.
Future<T> withBlockingProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Flexible(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    if (navigator.canPop()) navigator.pop();
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
