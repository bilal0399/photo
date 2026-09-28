import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/scanner/document_scanner.dart';
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

  /// Processes [documents], [concurrency] at a time so downloads and uploads
  /// overlap with the image work (which runs on background isolates).
  ///
  /// Reports come back in the order of [documents]. Cancelling stops new
  /// documents from starting; the ones already in flight are finished.
  Future<List<RescanReport>> run({
    required List<Document> documents,
    required ScanFilter filter,
    required bool backupOriginals,
    required void Function(int done, int total, Document current) onProgress,
    required bool Function() isCancelled,
    int concurrency = 2,
  }) async {
    Directory? backupDir;
    if (backupOriginals) {
      backupDir = await backupDirectory();
      await backupDir.create(recursive: true);
    }

    final total = documents.length;
    final results = List<RescanReport?>.filled(total, null);
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (next < total && !isCancelled()) {
        final index = next++;
        final doc = documents[index];
        onProgress(done, total, doc);
        results[index] = await _process(doc, filter, backupDir);
        done++;
      }
    }

    await Future.wait([for (var i = 0; i < math.min(concurrency, total); i++) worker()]);
    if (documents.isNotEmpty) onProgress(done, total, documents.last);
    return results.whereType<RescanReport>().toList();
  }

  Future<RescanReport> _process(Document doc, ScanFilter filter, Directory? backupDir) async {
    String? processed;
    try {
      final bytes = await _service.attachmentBytes(doc.attachmentPath);
      if (bytes == null) {
        return RescanReport(
          document: doc,
          outcome: RescanOutcome.failed,
          message: 'تعذّر تحميل الصورة',
        );
      }

      if (backupDir != null) {
        final number = doc.bookNumber.isNotEmpty ? doc.bookNumber : doc.documentCode;
        final copy = File(p.join(backupDir.path, '${number}_${p.basename(doc.attachmentPath)}'));
        await copy.writeAsBytes(bytes, flush: true);
      }

      final scan = await scanBytes(bytes, filter: filter);
      if (scan == null) {
        return RescanReport(
          document: doc,
          outcome: RescanOutcome.failed,
          message: 'تعذّرت قراءة الصورة',
        );
      }

      processed = await writeScanToTemp(scan.output);
      await _service.replaceAttachment(doc, processed);

      return RescanReport(
        document: doc,
        outcome: scan.autoDetected ? RescanOutcome.cropped : RescanOutcome.enhanced,
      );
    } catch (e) {
      return RescanReport(document: doc, outcome: RescanOutcome.failed, message: '$e');
    } finally {
      // Hundreds of documents would otherwise pile up in the temp folder.
      if (processed != null) {
        try {
          await File(processed).delete();
        } on FileSystemException {
          // Already gone; nothing to clean up.
        }
      }
    }
  }
}

final bulkRescanServiceProvider =
    Provider<BulkRescanService>((ref) => BulkRescanService(ref.watch(documentsServiceProvider)));
