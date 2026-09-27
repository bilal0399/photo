import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../features/documents/service/documents_service.dart';
import '../../features/tasks/service/tasks_service.dart';

/// Builds a complete offline backup by pulling everything from Supabase:
/// all document + task records into an Excel workbook, plus every attachment
/// image downloaded from Storage, all packaged into one zip.
class CloudBackupService {
  CloudBackupService(this._docs, this._tasks);

  final DocumentsService _docs;
  final TasksService _tasks;

  String defaultFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'diwan_backup_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.zip';
  }

  Future<Uint8List> build() async {
    final docs = await _docs.all();
    final tasks = await _tasks.all();

    // --- records workbook ---
    final excel = Excel.createExcel();

    final ds = excel['الطلبات'];
    ds.appendRow([
      for (final h in ['المعرّف', 'رقم الكتاب', 'التاريخ', 'النوع', 'الجهة', 'الحالة', 'الحركة', 'الملخص', 'تاريخ الموافقة'])
        TextCellValue(h),
    ]);
    for (final d in docs) {
      ds.appendRow([
        TextCellValue(d.documentCode),
        TextCellValue(d.bookNumber),
        TextCellValue(d.datetime),
        TextCellValue(d.bookType),
        TextCellValue(d.requester),
        TextCellValue(d.status),
        TextCellValue(d.direction),
        TextCellValue(d.summary),
        TextCellValue(d.approvalDate),
      ]);
    }

    final ts = excel['المهمات'];
    ts.appendRow([for (final h in ['رقم المهمة', 'الجهة']) TextCellValue(h)]);
    for (final t in tasks) {
      ts.appendRow([TextCellValue(t.taskNumber), TextCellValue(t.entity)]);
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final xlsx = excel.encode() ?? <int>[];

    // --- assemble zip ---
    final archive = Archive();
    archive.addFile(ArchiveFile('records.xlsx', xlsx.length, xlsx));

    for (final d in docs) {
      if (d.attachmentPath.isEmpty) continue;
      final bytes = await _docs.attachmentBytes(d.attachmentPath);
      if (bytes == null) continue;
      final name = 'images/documents/${d.bookNumber}_${p.basename(d.attachmentPath)}';
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    for (final t in tasks) {
      if (t.attachmentPath.isEmpty) continue;
      final bytes = await _tasks.attachmentBytes(t.attachmentPath);
      if (bytes == null) continue;
      final name = 'images/tasks/${t.taskNumber}_${p.basename(t.attachmentPath)}';
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final zip = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zip);
  }
}

final cloudBackupServiceProvider = Provider<CloudBackupService>(
  (ref) => CloudBackupService(
    ref.watch(documentsServiceProvider),
    ref.watch(tasksServiceProvider),
  ),
);
