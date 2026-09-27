import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/attachments/attachment_actions.dart';
import '../../../core/scanner/rescan_attachment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/image_viewer.dart';
import '../controller/documents_controller.dart';
import '../model/document.dart';
import '../service/documents_service.dart';

class DocumentDetailsPage extends ConsumerStatefulWidget {
  const DocumentDetailsPage({super.key, required this.document});

  final Document document;

  @override
  ConsumerState<DocumentDetailsPage> createState() => _DocumentDetailsPageState();
}

class _DocumentDetailsPageState extends ConsumerState<DocumentDetailsPage> {
  late Document _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.document;
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Downloads the cloud attachment to a temp file so the local viewer/printer
  /// can use it.
  Future<String?> _download() async {
    final bytes = await ref.read(documentsServiceProvider).attachmentBytes(_current.attachmentPath);
    if (bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, p.basename(_current.attachmentPath)));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _runWithDownload(Future<void> Function(String path) action) async {
    setState(() => _busy = true);
    final path = await _download();
    if (mounted) setState(() => _busy = false);
    if (path == null) {
      _snack('تعذّر تحميل المرفق. تحقّق من الاتصال.');
      return;
    }
    await action(path);
  }

  /// Re-processes an already uploaded image: crop/enhance it like a scan, store
  /// the result as the document's attachment and delete the original object.
  Future<void> _rescanAttachment() async {
    final service = ref.read(documentsServiceProvider);
    final processed = await rescanStoredImage(
      context,
      storagePath: _current.attachmentPath,
      download: () => service.attachmentBytes(_current.attachmentPath),
    );
    if (processed == null || !mounted) return;

    try {
      await withBlockingProgress(
        context,
        'جارٍ رفع الصورة بعد المعالجة...',
        () => ref.read(documentsControllerProvider).replaceAttachment(_current, processed),
      );
      final refreshed = await ref.read(documentsProvider.future);
      if (!mounted) return;
      setState(() => _current = refreshed.firstWhere(
            (d) => d.id == _current.id,
            orElse: () => _current,
          ));
      _snack('تمت معالجة الصورة وحفظها');
    } catch (e) {
      _snack('تعذّر حفظ الصورة المعالجة: $e');
    }
  }

  Color _statusColor() => switch (_current.status) {
        'قيد المراجعة' => AppColors.secondary,
        'تمت الموافقة' => AppColors.primary,
        'مرفوض' => AppColors.danger,
        'تقييم' => AppColors.warning,
        _ => const Color(0xFF475467),
      };

  /// Move to the adjacent document within the current filtered list (cyclic).
  void _navigate(List<Document> list, int delta) {
    if (list.length < 2) return;
    final index = list.indexWhere((d) => d.id == _current.id);
    final base = index < 0 ? 0 : index;
    final next = (base + delta + list.length) % list.length;
    setState(() => _current = list[next]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(documentsProvider).valueOrNull ?? [_current];
    final canNavigate = list.length > 1;
    final position = list.indexWhere((d) => d.id == _current.id);
    final number = _current.bookNumber.isNotEmpty ? _current.bookNumber : '#${_current.id}';

    final fields = <(String, String)>[
      ('المعرّف', _current.documentCode),
      ('رقم الكتاب', number),
      ('التاريخ والوقت', _current.datetime),
      (entityLabel(_current.direction), _current.requester),
      ('النوع', _current.bookType),
      ('نوع الحركة', _current.direction),
      if (_current.status == kApprovedStatus && _current.approvalDate.isNotEmpty)
        ('تاريخ الموافقة', _current.approvalDate),
      ('تاريخ الإنشاء', _current.createdAt),
      if ((_current.updatedAt ?? '').isNotEmpty) ('آخر تعديل', _current.updatedAt!),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('طلب رقم $number'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _statusColor(), borderRadius: BorderRadius.circular(16)),
              child: Text(_current.status,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: ListView(
              key: ValueKey(_current.id),
              padding: const EdgeInsets.all(20),
              children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [for (final f in fields) _tile(context, f.$1, f.$2)]),
                ),
              ),
              const SizedBox(height: 16),
              Text('ملخص الكتاب', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_current.summary, style: theme.textTheme.bodyLarge),
                ),
              ),
              const SizedBox(height: 20),
              if (_current.hasAttachment) _actions(context),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canNavigate ? () => _navigate(list, -1) : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('السابق'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  canNavigate && position >= 0 ? '${position + 1} / ${list.length}' : '—',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                ),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canNavigate ? () => _navigate(list, 1) : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('التالي'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _runWithDownload((path) async {
                          if (!mounted) return;
                          if (_current.isImageAttachment) {
                            await showImageViewer(context, path);
                          } else {
                            await openExternally(path);
                          }
                        }),
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_current.isImageAttachment
                        ? Icons.image_outlined
                        : Icons.folder_open_outlined),
                label: Text(_current.isImageAttachment ? 'عرض الصورة' : 'فتح الملف'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _runWithDownload(printAttachment),
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة'),
              ),
            ),
          ],
        ),
        // Older records were attached as plain photos; this re-runs them
        // through the scanner (crop, straighten, enhance).
        if (_current.isImageAttachment) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _rescanAttachment,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('معالجة الصورة كسكانر'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      subtitle: Text(value, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
