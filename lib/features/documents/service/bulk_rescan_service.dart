import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/scanner/document_scanner.dart';
import '../../../core/scanner/scan_flow.dart';
import '../model/document.dart';
import 'documents_service.dart';

enum RescanOutcome {
  cropped('تم الاقتصاص والتحسين'),
  enhanced('تحسين فقط (لم تُكشف الحواف)'),
  failed('فشل');

  const RescanOutcome(this.label);

  final String label;
}

class RescanReport {
  const RescanReport({required this.document, required this.outcome, this.message});

  final Document document;
  final RescanOutcome outcome;
  final String? message;

  String get title {
    final number = document.bookNumber.isNotEmpty ? document.bookNumber : document.documentCode;
    return 'طلب $number';
  }
}

/// Batch version of the scanner: crops, straightens and enhances every stored
/// image without opening each document.
///
/// Edge detection decides per image; when the sheet is not clearly separated
/// from its background the frame is kept whole and only the filter is applied,
/// so a weak detection never eats part of a document.
class BulkRescanService {
  BulkRescanService(this._service);

  final DocumentsService _service;

  /// Documents still holding an unprocessed image attachment.
  List<Document> pending(List<Document> documents) => [
        for (final d in documents)
          if (d.hasAttachment && isScannable(d.attachmentPath) && !isProcessedScan(d.attachmentPath))
            d,
      ];

  /// Folder where originals are copied before they are replaced.
  Future<Directory> backupDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'diwan_originals'));
  }

  Future<List<RescanReport>> run({
    required List<Document> documents,
    required ScanFilter filter,
    required bool backupOriginals,
    required void Function(int done, int total, Document current) onProgress,
    required bool Function() isCancelled,
  }) async {
    final reports = <RescanReport>[];
    final temp = await getTemporaryDirectory();
    Directory? backupDir;
    if (backupOriginals) {
      backupDir = await backupDirectory();
      await backupDir.create(recursive: true);
    }

    for (var i = 0; i < documents.length; i++) {
      if (isCancelled()) break;
      final doc = documents[i];
      onProgress(i, documents.length, doc);
      try {
        final bytes = await _service.attachmentBytes(doc.attachmentPath);
        if (bytes == null) {
          reports.add(RescanReport(
            document: doc,
            outcome: RescanOutcome.failed,
            message: 'تعذّر تحميل الصورة',
          ));
          continue;
        }

        if (backupDir != null) {
          final number = doc.bookNumber.isNotEmpty ? doc.bookNumber : doc.documentCode;
          final copy = File(p.join(backupDir.path, '${number}_${p.basename(doc.attachmentPath)}'));
          await copy.writeAsBytes(bytes, flush: true);
        }

        final source = File(p.join(temp.path,
            'bulk_${DateTime.now().microsecondsSinceEpoch}${p.extension(doc.attachmentPath)}'));
        await source.writeAsBytes(bytes, flush: true);

        final prep = await prepareScan(source.path);
        if (prep == null) {
          reports.add(RescanReport(
            document: doc,
            outcome: RescanOutcome.failed,
            message: 'تعذّرت قراءة الصورة',
          ));
          continue;
        }

        final output = await renderScan(ScanRequest(
          bytes: prep.bytes,
          quad: prep.quad,
          filterIndex: filter.index,
          quarterTurns: 0,
        ));
        final processed = await writeScanToTemp(output);
        await _service.replaceAttachment(doc, processed);

        reports.add(RescanReport(
          document: doc,
          outcome: prep.autoDetected ? RescanOutcome.cropped : RescanOutcome.enhanced,
        ));
      } catch (e) {
        reports.add(RescanReport(document: doc, outcome: RescanOutcome.failed, message: '$e'));
      }
    }
    if (documents.isNotEmpty) onProgress(reports.length, documents.length, documents.last);
    return reports;
  }
}

final bulkRescanServiceProvider =
    Provider<BulkRescanService>((ref) => BulkRescanService(ref.watch(documentsServiceProvider)));
