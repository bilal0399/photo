import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/sort_bar.dart';
import '../../options/service/options_service.dart';
import '../controller/documents_controller.dart';
import '../model/document.dart';
import '../model/document_filters.dart';
import '../service/document_export_service.dart';
import 'widgets/document_card.dart';

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  final _bookNumber = TextEditingController();
  final _summary = TextEditingController();
  final _day = TextEditingController();

  @override
  void dispose() {
    _bookNumber.dispose();
    _summary.dispose();
    _day.dispose();
    super.dispose();
  }

  DocumentFilters get _filters => ref.read(documentFiltersProvider);
  void _set(DocumentFilters f) => ref.read(documentFiltersProvider.notifier).update(f);

  void _reset() {
    _bookNumber.clear();
    _summary.clear();
    _day.clear();
    ref.read(documentFiltersProvider.notifier).reset();
  }

  Future<void> _export(List<Document> docs) async {
    if (docs.isEmpty) {
      _snack('لا توجد بيانات لتصديرها');
      return;
    }
    final service = ref.read(documentExportServiceProvider);
    final bytes = service.buildXlsx(docs);
    if (bytes == null) return;
    final name = service.defaultFileName();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final tmp = await getTemporaryDirectory();
        final path = p.join(tmp.path, name);
        await File(path).writeAsBytes(bytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'تصدير الطلبات'));
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [XTypeGroup(label: 'Excel', extensions: ['xlsx'])],
        );
        if (location == null) return;
        await File(location.path).writeAsBytes(bytes);
        _snack('تم حفظ الملف:\n${location.path}');
      }
    } catch (e) {
      _snack('خطأ: $e');
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(Document doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الكتاب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await ref.read(documentsControllerProvider).remove(doc);
  }

  List<Document> _visible(List<Document> docs, DocumentFilters filters, SortState sort) =>
      applySort(filterDocuments(docs, filters), sort,
          numberOf: (d) => d.bookNumber, dateOf: (d) => d.datetime);

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final sort = ref.watch(documentSortProvider);
    final filters = ref.watch(documentFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الطلبات'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'إعادة تعيين',
            onPressed: _reset,
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
          IconButton(
            tooltip: 'تصدير Excel',
            onPressed: () => _export(_visible(docsAsync.valueOrNull ?? const [], filters, sort)),
            icon: const Icon(Icons.table_view_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // The shell keeps every branch alive, so the buttons of the hidden
        // sections share this subtree and each needs its own hero tag.
        heroTag: 'fab-documents',
        onPressed: () => context.push('/document-form'),
        icon: const Icon(Icons.add),
        label: const Text('إضافة طلب'),
      ),
      body: Column(
        children: [
          _FilterPanel(
            bookNumber: _bookNumber,
            summary: _summary,
            day: _day,
            onChanged: _set,
            current: () => _filters,
          ),
          SortBar(
            state: sort,
            onFieldChanged: (f) =>
                ref.read(documentSortProvider.notifier).state = sort.withField(f),
            onToggleDirection: () =>
                ref.read(documentSortProvider.notifier).state = sort.toggleDirection(),
          ),
          Expanded(
            child: docsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (docs) {
                final sorted = _visible(docs, filters, sort);
                if (sorted.isEmpty) {
                  return const EmptyState(icon: Icons.inbox_outlined, text: 'لا توجد نتائج');
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: context.gridColumns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) => DocumentCard(
                    document: sorted[i],
                    onOpen: () => context.push('/document-details', extra: sorted[i]),
                    onEdit: () => context.push('/document-form', extra: sorted[i]),
                    onDelete: () => _confirmDelete(sorted[i]),
                  )
                      .animate()
                      .fadeIn(duration: 260.ms, delay: (28 * (i % 12)).ms)
                      .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPanel extends ConsumerWidget {
  const _FilterPanel({
    required this.bookNumber,
    required this.summary,
    required this.day,
    required this.onChanged,
    required this.current,
  });

  final TextEditingController bookNumber;
  final TextEditingController summary;
  final TextEditingController day;
  final ValueChanged<DocumentFilters> onChanged;
  final DocumentFilters Function() current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final years = ref.watch(distinctYearsProvider);
    final bookTypes = ref.watch(optionValuesProvider('book_type')).valueOrNull ?? const [];
    final requesters = ref.watch(optionValuesProvider('requester')).valueOrNull ?? const [];
    final serverRecipients = ref.watch(optionValuesProvider('recipient')).valueOrNull ?? const [];
    final statuses = ref.watch(optionValuesProvider('status')).valueOrNull ?? const [];
    // Both sides of the correspondence live in the same field, so the filter
    // offers incoming senders and outgoing recipients together.
    final parties = <String>{
      ...requesters,
      ...(serverRecipients.isNotEmpty ? serverRecipients : kDefaultRecipients),
    }.toList();
    final f = current();
    final fields = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _text(bookNumber, 'رقم الكتاب', (v) => onChanged(f.copyWith(bookNumber: v))),
        _text(summary, 'بحث في الملخص', (v) => onChanged(f.copyWith(summary: v))),
        _dropdown('السنة', f.year, years, (v) => onChanged(f.copyWith(year: v ?? ''))),
        _dropdown('الشهر', f.month, List.generate(12, (i) => '${i + 1}'),
            (v) => onChanged(f.copyWith(month: v ?? ''))),
        _text(day, 'اليوم', (v) => onChanged(f.copyWith(day: v))),
        _dropdown('النوع', f.bookType, bookTypes, (v) => onChanged(f.copyWith(bookType: v ?? ''))),
        _dropdown('الجهة', f.requester, parties, (v) => onChanged(f.copyWith(requester: v ?? ''))),
        _dropdown('الحالة', f.status, statuses, (v) => onChanged(f.copyWith(status: v ?? ''))),
        _dropdown('الحركة', f.direction, kDirections,
            (v) => onChanged(f.copyWith(direction: v ?? ''))),
      ],
    );

    // On phones the filters collapse behind a tap (native pattern); on wider
    // screens they stay open as a toolbar.
    if (context.isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Card(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.tune),
              title: const Text('بحث وتصفية'),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              children: [
                // Cap the expanded height and scroll internally so it never
                // overflows the fixed area above the results grid.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                  ),
                  child: SingleChildScrollView(child: fields),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Card(child: Padding(padding: const EdgeInsets.all(12), child: fields)),
    );
  }

  Widget _text(TextEditingController controller, String label, ValueChanged<String> onChanged) => SizedBox(
        width: 200,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: onChanged,
        ),
      );

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) =>
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String>(
          initialValue: value.isEmpty ? null : value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            const DropdownMenuItem(value: '', child: Text('الكل')),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: onChanged,
        ),
      );
}
