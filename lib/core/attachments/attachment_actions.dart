import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const _imageExt = {'.png', '.jpg', '.jpeg'};

/// Opens an attachment with the OS default application.
Future<void> openExternally(String path) async {
  await OpenFilex.open(path);
}

/// Sends an attachment to the printer. Images are wrapped in a PDF page; PDFs
/// print directly; everything else falls back to opening externally.
Future<void> printAttachment(String path) async {
  final ext = p.extension(path).toLowerCase();
  if (_imageExt.contains(ext)) {
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(onLayout: (format) async {
      final doc = pw.Document();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
      return doc.save();
    });
  } else if (ext == '.pdf') {
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  } else {
    await openExternally(path);
  }
}
