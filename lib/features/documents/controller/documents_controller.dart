import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/sort_bar.dart';
import '../model/document.dart';
import '../model/document_filters.dart';
import '../service/documents_service.dart';

/// Current sort choice for the documents list.
final documentSortProvider = StateProvider<SortState>((_) => const SortState(SortField.date));

/// Current filter state driving the visible list.
final documentFiltersProvider =
    NotifierProvider<DocumentFiltersController, DocumentFilters>(DocumentFiltersController.new);

class DocumentFiltersController extends Notifier<DocumentFilters> {
  @override
  DocumentFilters build() => const DocumentFilters();
  void update(DocumentFilters filters) => state = filters;
  void reset() => state = const DocumentFilters();
}

/// The full document list (online-first, cached). Filtering and sorting happen
/// client-side over this list.
final documentsProvider =
    FutureProvider<List<Document>>((ref) => ref.watch(documentsServiceProvider).all());

/// Years present in the data, for the filter dropdown.
final distinctYearsProvider = Provider<List<String>>((ref) {
  final docs = ref.watch(documentsProvider).valueOrNull ?? const [];
  final years = <String>{
    for (final d in docs)
      if (d.datetime.length >= 4) d.datetime.substring(0, 4),
  }..removeWhere((y) => y.isEmpty);
  return years.toList()..sort((a, b) => b.compareTo(a));
});

/// Applies the active filters to a document list (mirrors the old SQL search).
List<Document> filterDocuments(List<Document> docs, DocumentFilters f) {
  int? monthOf(String dt) => dt.length >= 7 ? int.tryParse(dt.substring(5, 7)) : null;
  int? dayOf(String dt) => dt.length >= 10 ? int.tryParse(dt.substring(8, 10)) : null;

  bool ok(Document d) {
    if (f.bookNumber.isNotEmpty && d.bookNumber != f.bookNumber) return false;
    if (f.summary.isNotEmpty && !d.summary.contains(f.summary)) return false;
    if (f.year.isNotEmpty && !(d.datetime.length >= 4 && d.datetime.substring(0, 4) == f.year)) {
      return false;
    }
    if (f.month.isNotEmpty && monthOf(d.datetime) != int.tryParse(f.month)) return false;
    if (f.day.isNotEmpty && dayOf(d.datetime) != int.tryParse(f.day)) return false;
    if (f.bookType.isNotEmpty && d.bookType != f.bookType) return false;
    if (f.requester.isNotEmpty && d.requester != f.requester) return false;
    if (f.status.isNotEmpty && d.status != f.status) return false;
    if (f.direction.isNotEmpty && d.direction != f.direction) return false;
    return true;
  }

  return docs.where(ok).toList();
}

/// Intent methods for creating/editing/deleting, refreshing the list after.
class DocumentsController {
  DocumentsController(this.ref);
  final Ref ref;

  DocumentsService get _service => ref.read(documentsServiceProvider);

  Future<String> nextBookNumber() async {
    final docs = ref.read(documentsProvider).valueOrNull ?? await _service.all();
    var max = 0;
    for (final d in docs) {
      final n = int.tryParse(d.bookNumber);
      if (n != null && n > max) max = n;
    }
    return '${max + 1}';
  }

  Future<void> create(DocumentDraft draft, {String? sourceAttachmentPath}) async {
    await _service.create(draft, sourceAttachmentPath: sourceAttachmentPath);
    ref.invalidate(documentsProvider);
  }

  Future<void> edit(Document doc, DocumentDraft draft, {String? newSourceAttachmentPath}) async {
    await _service.edit(doc, draft, newSourceAttachmentPath: newSourceAttachmentPath);
    ref.invalidate(documentsProvider);
  }

  /// Swaps in a scanner-processed copy of the attachment and drops the old one.
  Future<void> replaceAttachment(Document doc, String localPath) async {
    await _service.replaceAttachment(doc, localPath);
    ref.invalidate(documentsProvider);
  }

  Future<void> remove(Document doc, {bool deleteFile = true}) async {
    await _service.remove(doc, deleteFile: deleteFile);
    ref.invalidate(documentsProvider);
  }
}

final documentsControllerProvider = Provider<DocumentsController>(DocumentsController.new);
