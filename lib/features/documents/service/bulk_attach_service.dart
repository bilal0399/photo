import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/scanner/document_scanner.dart';
import '../model/document.dart';
import 'documents_service.dart';

/// File types that can be attached in bulk.
const kBulkAttachExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

/// Where a picked file stands before anything is uploaded.
enum AttachStatus {
  ready('جاهز للإرفاق'),
  replaces('سيستبدل المرفق الحالي'),
  hasAttachment('للطلب مرفق مسبقاً'),
  notFound('لا يوجد طلب بهذا الرقم'),
  ambiguous('أكثر من طلب بهذا الرقم'),
  duplicateFile('ملف آخر لنفس الطلب'),
  badName('اسم الملف ليس رقماً'),
  unsupported('نوع ملف غير مدعوم');

  const AttachStatus(this.label);

  final String label;

  bool get willUpload => this == ready || this == replaces;
}

class AttachItem {
  const AttachItem({
    required this.path,
    required this.status,
    this.number,
    this.document,
    this.candidates = const [],
  });

  final String path;
  final AttachStatus status;

  /// Book number read from the file name.
  final String? number;

  /// The matched document, when there is exactly one.
  final Document? document;

  /// Every document carrying [number] when the match is ambiguous.
  final List<Document> candidates;

  String get fileName => p.basename(path);
}

enum AttachOutcome {
  cropped('أُرفقت بعد الاقتصاص والتحسين'),
  enhanced('أُرفقت بعد التحسين (لم تُكشف الحواف)'),
  attached('أُرفقت كما هي'),
  failed('فشل');

  const AttachOutcome(this.label);

  final String label;
}

class AttachReport {
  const AttachReport({required this.item, required this.outcome, this.message});

  final AttachItem item;
  final AttachOutcome outcome;
  final String? message;
}

/// Attaches many files at once: each file is named after the book number of
/// the document it belongs to ("7.jpg" goes to book 7).
class BulkAttachService {
  BulkAttachService(this._service);

  final DocumentsService _service;

  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// The book number a file name stands for, or null when it is not a number.
  /// Arabic-Indic digits and leading zeros are accepted ("٠٠٧.jpg" is 7).
  static String? numberFromName(String path) {
    final buffer = StringBuffer();
    for (final ch in p.basenameWithoutExtension(path).trim().split('')) {
      final arabic = _arabicDigits.indexOf(ch);
      final persian = _persianDigits.indexOf(ch);
      buffer.write(arabic >= 0 ? '$arabic' : (persian >= 0 ? '$persian' : ch));
    }
    final value = int.tryParse(buffer.toString());
    return value == null || value < 0 ? null : '$value';
  }

  /// Matches each file to a document. [year] (e.g. "2025") and [direction]
  /// narrow the documents considered, which settles numbers that repeat
  /// across years or directions.
  List<AttachItem> plan(
    List<String> files,
    List<Document> documents, {
    String? year,
    String? direction,
    bool replaceExisting = false,
  }) {
    final byNumber = <String, List<Document>>{};
    for (final d in documents) {
      if (year != null && year.isNotEmpty && !d.datetime.startsWith(year)) continue;
      if (direction != null && direction.isNotEmpty && d.direction != direction) continue;
      final n = int.tryParse(d.bookNumber.trim());
      if (n == null) continue;
      byNumber.putIfAbsent('$n', () => []).add(d);
    }

    final claimed = <String>{};
    final items = <AttachItem>[];
    for (final path in files) {
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      if (!kBulkAttachExtensions.contains(ext)) {
        items.add(AttachItem(path: path, status: AttachStatus.unsupported));
        continue;
      }
      final number = numberFromName(path);
      if (number == null) {
        items.add(AttachItem(path: path, status: AttachStatus.badName));
        continue;
      }
      final matches = byNumber[number] ?? const <Document>[];
      if (matches.isEmpty) {
        items.add(AttachItem(path: path, number: number, status: AttachStatus.notFound));
        continue;
      }
      if (matches.length > 1) {
        items.add(AttachItem(
          path: path,
          number: number,
          status: AttachStatus.ambiguous,
          candidates: matches,
        ));
        continue;
      }
      final doc = matches.single;
      final AttachStatus status;
      if (!claimed.add(doc.id ?? doc.documentCode)) {
        status = AttachStatus.duplicateFile;
      } else if (doc.hasAttachment) {
        status = replaceExisting ? AttachStatus.replaces : AttachStatus.hasAttachment;
      } else {
        status = AttachStatus.ready;
      }
      items.add(AttachItem(path: path, number: number, document: doc, status: status));
    }
    return items;
  }

  /// Uploads every item that [AttachStatus.willUpload]. Images are cropped and
  /// enhanced with [filter] first unless [enhance] is false.
  Future<List<AttachReport>> run({
    required List<AttachItem> items,
    required bool enhance,
    required ScanFilter filter,
    required void Function(int done, int total, AttachItem current) onProgress,
    required bool Function() isCancelled,
    int concurrency = 2,
  }) async {
    final work = [for (final item in items) if (item.status.willUpload) item];
    final total = work.length;
    final results = List<AttachReport?>.filled(total, null);
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (next < total && !isCancelled()) {
        final index = next++;
        onProgress(done, total, work[index]);
        results[index] = await _attach(work[index], enhance, filter);
        done++;
      }
    }

    await Future.wait([for (var i = 0; i < math.min(concurrency, total); i++) worker()]);
    if (work.isNotEmpty) onProgress(done, total, work.last);
    return results.whereType<AttachReport>().toList();
  }

  Future<AttachReport> _attach(AttachItem item, bool enhance, ScanFilter filter) async {
    String? processed;
    try {
      var outcome = AttachOutcome.attached;
      var upload = item.path;
      if (enhance && isScannable(item.path)) {
        final scan = await scanFile(item.path, filter: filter);
        if (scan == null) {
          return AttachReport(item: item, outcome: AttachOutcome.failed, message: 'تعذّرت قراءة الصورة');
        }
        processed = await writeScanToTemp(scan.output);
        upload = processed;
        outcome = scan.autoDetected ? AttachOutcome.cropped : AttachOutcome.enhanced;
      }
      await _service.replaceAttachment(item.document!, upload);
      return AttachReport(item: item, outcome: outcome);
    } catch (e) {
      return AttachReport(item: item, outcome: AttachOutcome.failed, message: '$e');
    } finally {
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

final bulkAttachServiceProvider =
    Provider<BulkAttachService>((ref) => BulkAttachService(ref.watch(documentsServiceProvider)));
