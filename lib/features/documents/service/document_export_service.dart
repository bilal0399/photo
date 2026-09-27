import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/document.dart';

/// Builds an .xlsx workbook (as bytes) from a list of documents. The caller
/// decides where to save/share the bytes (chosen path on desktop, share sheet
/// on mobile).
class DocumentExportService {
  List<int>? buildXlsx(List<Document> documents) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet()!;
    final sheet = excel[sheetName];

    const headers = [
      'المعرّف',
      'رقم الكتاب',
      'التاريخ',
      'النوع',
      'الجهة',
      'الحالة',
      'الحركة',
      'الملخص',
      'تاريخ الموافقة',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final d in documents) {
      sheet.appendRow([
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
    return excel.encode();
  }

  String defaultFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'documents_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.xlsx';
  }
}

final documentExportServiceProvider = Provider<DocumentExportService>((ref) => DocumentExportService());
