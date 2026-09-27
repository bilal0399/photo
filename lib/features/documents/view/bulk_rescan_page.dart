import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scanner/document_scanner.dart';
import '../controller/documents_controller.dart';
import '../model/document.dart';
import '../service/bulk_rescan_service.dart';

/// Processes every old document image in one run: download, detect the sheet,
/// crop, enhance, upload and delete the original — without opening each record.
class BulkRescanPage extends ConsumerStatefulWidget {
  const BulkRescanPage({super.key});

  @override
  ConsumerState<BulkRescanPage> createState() => _BulkRescanPageState();
}

class _BulkRescanPageState extends ConsumerState<BulkRescanPage> {
  ScanFilter _filter = ScanFilter.auto;
  bool _backupOriginals = true;

  bool _running = false;
  bool _cancelRequested = false;
  int _done = 0;
  int _total = 0;
  String _currentLabel = '';
  List<RescanReport>? _reports;
  String? _backupPath;

  Future<void> _start(List<Document> pending) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المعالجة'),
        content: Text(
          'ستتم معالجة ${pending.length} صورة: اقتصاص الحواف وتحسينها، '
          'ثم استبدال الصورة الأصلية وحذفها من التخزين.'
          '${_backupOriginals ? '\n\nسيتم حفظ نسخة من الصور الأصلية على هذا الجهاز قبل الحذف.' : '\n\nلن يتم حفظ أي نسخة من الأصل. لا يمكن التراجع.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ابدأ')),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = ref.read(bulkRescanServiceProvider);
    setState(() {
      _running = true;
      _cancelRequested = false;
      _done = 0;
      _total = pending.length;
      _reports = null;
      _currentLabel = '';
    });

    try {
      final backup = _backupOriginals ? (await service.backupDirectory()).path : null;
      final reports = await service.run(
        documents: pending,
        filter: _filter,
        backupOriginals: _backupOriginals,
        isCancelled: () => _cancelRequested,
        onProgress: (done, total, current) {
          if (!mounted) return;
          final number =
              current.bookNumber.isNotEmpty ? current.bookNumber : current.documentCode;
          setState(() {
            _done = done;
            _total = total;
            _currentLabel = 'طلب $number';
          });
        },
      );
      ref.invalidate(documentsProvider);
      if (!mounted) return;
      setState(() {
        _running = false;
        _reports = reports;
        _backupPath = backup;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّرت المعالجة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docsAsync = ref.watch(documentsProvider);
    final service = ref.watch(bulkRescanServiceProvider);
    final all = docsAsync.valueOrNull ?? const <Document>[];
    final pending = service.pending(all);

    return Scaffold(
      appBar: AppBar(title: const Text('معالجة الصور القديمة')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        docsAsync.isLoading
                            ? 'جارٍ قراءة الطلبات...'
                            : 'صور بانتظار المعالجة: ${pending.length} من أصل ${all.length} طلب',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تُقتص حواف الورقة تلقائياً لكل صورة. إذا لم تظهر الحواف بوضوح '
                        'تبقى الصورة كاملة ويُطبَّق التحسين فقط، حتى لا يُقتطع جزء من الكتاب.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('نوع المعالجة', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in ScanFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: _running ? null : (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _backupOriginals,
                onChanged: _running ? null : (v) => setState(() => _backupOriginals = v),
                title: const Text('حفظ نسخة من الصور الأصلية على هذا الجهاز'),
                subtitle: const Text('مجلد diwan_originals داخل مستنداتك — يُنصح بإبقائه مفعّلاً'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'بعد نجاح المعالجة تُحذف الصورة الأصلية من التخزين السحابي نهائياً.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_running) ...[
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                const SizedBox(height: 10),
                Text('$_done / $_total   —   $_currentLabel', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(_cancelRequested ? 'جارٍ الإيقاف بعد الصورة الحالية...' : 'إيقاف'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: pending.isEmpty ? null : () => _start(pending),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(
                    pending.isEmpty ? 'لا توجد صور بحاجة للمعالجة' : 'بدء معالجة ${pending.length} صورة',
                  ),
                ),
              if (_reports != null) ...[
                const SizedBox(height: 20),
                _summary(_reports!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(List<RescanReport> reports) {
    final theme = Theme.of(context);
    final cropped = reports.where((r) => r.outcome == RescanOutcome.cropped).length;
    final enhanced = reports.where((r) => r.outcome == RescanOutcome.enhanced).length;
    final failed = reports.where((r) => r.outcome == RescanOutcome.failed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('النتيجة', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تم اقتصاصها وتحسينها: $cropped'),
                Text('تحسين فقط (لم تُكشف الحواف): $enhanced'),
                Text('فشلت: ${failed.length}'),
                if (_backupPath != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'نسخ الصور الأصلية محفوظة في:\n$_backupPath',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('الطلبات التي فشلت', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final report in failed)
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline),
                title: Text(report.title),
                subtitle: Text(report.message ?? report.outcome.label),
              ),
            ),
        ],
      ],
    );
  }
}
