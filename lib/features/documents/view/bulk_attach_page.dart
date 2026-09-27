import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scanner/document_scanner.dart';
import '../controller/documents_controller.dart';
import '../model/document.dart';
import '../service/bulk_attach_service.dart';

/// Attaches a whole folder of scans in one go: every file is named after the
/// book number of its document ("7.jpg" goes to book 7).
class BulkAttachPage extends ConsumerStatefulWidget {
  const BulkAttachPage({super.key});

  @override
  ConsumerState<BulkAttachPage> createState() => _BulkAttachPageState();
}

class _BulkAttachPageState extends ConsumerState<BulkAttachPage> {
  final _files = <String>[];
  String _year = '';
  String _direction = '';
  bool _replaceExisting = false;
  bool _enhance = true;
  ScanFilter _filter = ScanFilter.auto;
  bool _dragging = false;

  bool _running = false;
  bool _cancelRequested = false;
  int _done = 0;
  int _total = 0;
  String _currentLabel = '';
  List<AttachReport>? _reports;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  void _addFiles(Iterable<String> paths) {
    setState(() {
      for (final path in paths) {
        if (!_files.contains(path)) _files.add(path);
      }
      _reports = null;
    });
  }

  Future<void> _pick() async {
    final files = await openFiles(
      acceptedTypeGroups: const [XTypeGroup(label: 'صور و PDF', extensions: kBulkAttachExtensions)],
    );
    if (files.isNotEmpty) _addFiles(files.map((f) => f.path));
  }

  Future<void> _start(List<AttachItem> items) async {
    final uploads = items.where((i) => i.status.willUpload).toList();
    final replacing = uploads.where((i) => i.status == AttachStatus.replaces).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الإرفاق'),
        content: Text(
          'سيتم إرفاق ${uploads.length} ملف بطلباتها'
          '${_enhance ? ' بعد اقتصاص الصور وتحسينها' : ''}.'
          '${replacing > 0 ? '\n\nسيُستبدل المرفق الحالي لـ $replacing طلب ويُحذف القديم نهائياً.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ابدأ')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _running = true;
      _cancelRequested = false;
      _done = 0;
      _total = uploads.length;
      _reports = null;
    });
    try {
      final reports = await ref.read(bulkAttachServiceProvider).run(
            items: items,
            enhance: _enhance,
            filter: _filter,
            isCancelled: () => _cancelRequested,
            onProgress: (done, total, current) {
              if (!mounted) return;
              setState(() {
                _done = done;
                _total = total;
                _currentLabel = 'طلب ${current.number}';
              });
            },
          );
      ref.invalidate(documentsProvider);
      if (!mounted) return;
      final attached = {for (final r in reports) if (r.outcome != AttachOutcome.failed) r.item.path};
      setState(() {
        _running = false;
        _reports = reports;
        _files.removeWhere(attached.contains);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الإرفاق: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docsAsync = ref.watch(documentsProvider);
    final docs = docsAsync.valueOrNull ?? const <Document>[];
    final years = ref.watch(distinctYearsProvider);
    final items = ref.read(bulkAttachServiceProvider).plan(
          _files,
          docs,
          year: _year,
          direction: _direction,
          replaceExisting: _replaceExisting,
        );
    final ready = items.where((i) => i.status.willUpload).length;
    final missingCount = docs.where((d) => !d.hasAttachment).length;

    return Scaffold(
      appBar: AppBar(title: const Text('إرفاق صور جماعي')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
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
                            : 'طلبات بدون مرفق: $missingCount من أصل ${docs.length}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'سمِّ كل ملف برقم الكتاب: الملف 7.jpg يُرفق بالطلب رقم 7. '
                        'تُقبل الأرقام العربية (٧) والأصفار في البداية (007).',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _dropArea(theme),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _year,
                      decoration: const InputDecoration(labelText: 'السنة'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('كل السنوات')),
                        for (final y in years) DropdownMenuItem(value: y, child: Text(y)),
                      ],
                      onChanged: _running ? null : (v) => setState(() => _year = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _direction,
                      decoration: const InputDecoration(labelText: 'نوع الحركة'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('الكل')),
                        for (final d in kDirections) DropdownMenuItem(value: d, child: Text(d)),
                      ],
                      onChanged: _running ? null : (v) => setState(() => _direction = v ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'حدِّد السنة أو نوع الحركة إذا كان رقم الكتاب يتكرر بينها.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              SwitchListTile(
                value: _enhance,
                onChanged: _running ? null : (v) => setState(() => _enhance = v),
                title: const Text('اقتصاص الصور وتحسينها قبل الإرفاق'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_enhance)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in ScanFilter.values.where((f) => f != ScanFilter.original))
                      ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: _running ? null : (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
              SwitchListTile(
                value: _replaceExisting,
                onChanged: _running ? null : (v) => setState(() => _replaceExisting = v),
                title: const Text('استبدال المرفق إذا كان للطلب مرفق مسبقاً'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              if (_running) ...[
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                const SizedBox(height: 10),
                Text('$_done / $_total   —   $_currentLabel', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(_cancelRequested ? 'جارٍ الإيقاف...' : 'إيقاف'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: ready == 0 ? null : () => _start(items),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(ready == 0 ? 'لا توجد ملفات جاهزة' : 'إرفاق $ready ملف'),
                ),
              if (_reports != null) ...[
                const SizedBox(height: 20),
                _summary(_reports!),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Text('الملفات (${items.length})', style: theme.textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: _running ? null : () => setState(_files.clear),
                      icon: const Icon(Icons.clear_all),
                      label: const Text('مسح القائمة'),
                    ),
                  ],
                ),
                for (final item in items) _itemTile(theme, item),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropArea(ThemeData theme) {
    final box = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _running ? null : _pick,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _dragging ? theme.colorScheme.primary : theme.colorScheme.secondary,
            width: _dragging ? 2.5 : 1.5,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.collections_outlined, size: 36, color: theme.hintColor),
              const SizedBox(height: 8),
              Text(
                _isMobile ? 'اضغط لاختيار الصور' : 'اسحب الصور هنا أو اضغط للاختيار',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
    if (_isMobile) return box;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        if (!_running) _addFiles(detail.files.map((f) => f.path));
      },
      child: box,
    );
  }

  Widget _itemTile(ThemeData theme, AttachItem item) {
    final ok = item.status.willUpload;
    final color = ok
        ? theme.colorScheme.primary
        : (item.status == AttachStatus.hasAttachment ? theme.hintColor : theme.colorScheme.error);
    final doc = item.document;
    final detail = switch (item.status) {
      AttachStatus.ambiguous =>
        '${item.status.label}: ${item.candidates.map((d) => '${d.direction} ${d.dateOnly}').join('، ')}',
      _ when doc != null => '${item.status.label} — ${doc.direction} ${doc.dateOnly} · ${doc.summary}',
      _ => item.status.label,
    };
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(ok ? Icons.check_circle_outline : Icons.info_outline, color: color),
        title: Text(item.fileName),
        subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: 'إزالة',
          icon: const Icon(Icons.close),
          onPressed: _running ? null : () => setState(() => _files.remove(item.path)),
        ),
      ),
    );
  }

  Widget _summary(List<AttachReport> reports) {
    final theme = Theme.of(context);
    final failed = reports.where((r) => r.outcome == AttachOutcome.failed).toList();
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
                for (final outcome in AttachOutcome.values)
                  if (reports.any((r) => r.outcome == outcome))
                    Text('${outcome.label}: ${reports.where((r) => r.outcome == outcome).length}'),
              ],
            ),
          ),
        ),
        for (final report in failed)
          Card(
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.error_outline),
              title: Text(report.item.fileName),
              subtitle: Text(report.message ?? report.outcome.label),
            ),
          ),
      ],
    );
  }
}
