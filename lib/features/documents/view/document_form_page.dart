import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/scanner/scan_flow.dart';
import '../../options/service/options_service.dart';
import '../controller/documents_controller.dart';
import '../model/document.dart';

const _attachmentExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx', 'xls', 'xlsx'];
const _imageExt = {'.png', '.jpg', '.jpeg'};
const _defaultStatus = 'قيد المراجعة';

class DocumentFormPage extends ConsumerStatefulWidget {
  const DocumentFormPage({super.key, this.document});

  final Document? document;
  bool get isEdit => document != null;

  @override
  ConsumerState<DocumentFormPage> createState() => _DocumentFormPageState();
}

class _DocumentFormPageState extends ConsumerState<DocumentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookNumber = TextEditingController();
  final _summary = TextEditingController();
  final _summaryFocus = FocusNode();

  final _day = TextEditingController();
  late int _year;
  late int _month;
  String? _bookType;
  String? _requester;
  String _status = _defaultStatus;
  String _direction = kOutgoing;
  String? _pickedAttachment;
  bool _dragging = false;
  bool _saving = false;
  bool _initialized = false;

  /// The number this form filled in by itself. While the field still holds it,
  /// changing the party is free to replace it; once the user types their own
  /// number it is left alone.
  String _suggestedNumber = '';

  String get _numberPrefix => numberPrefixFor(direction: _direction, party: _requester);

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    final date = doc != null ? _parseDate(doc.datetime) : DateTime.now();
    _year = date.year;
    _month = date.month;
    _day.text = '${date.day}';
    if (doc != null) {
      _bookNumber.text = doc.bookNumber;
      _summary.text = doc.summary;
      _status = doc.status;
      _direction = doc.direction.isNotEmpty ? doc.direction : kOutgoing;
    } else {
      _suggestNumber();
    }
  }

  /// Fills the number field with the next free number of the current series,
  /// unless the user already typed a number of their own.
  Future<void> _suggestNumber() async {
    final prefix = _numberPrefix;
    final current = _bookNumber.text.trim();
    if (current.isNotEmpty && current != _suggestedNumber) return;
    final next = await ref.read(documentsControllerProvider).nextBookNumber(prefix: prefix);
    if (!mounted) return;
    final stillOurs = _bookNumber.text.trim().isEmpty || _bookNumber.text.trim() == _suggestedNumber;
    if (!stillOurs || prefix != _numberPrefix) return;
    setState(() {
      _suggestedNumber = next;
      _bookNumber.text = next;
    });
  }

  DateTime _parseDate(String value) {
    final datePart = value.split(' ').first;
    return DateTime.tryParse(datePart) ?? DateTime.now();
  }

  /// Years offered in the dropdown; an older document keeps its own year.
  List<int> get _years {
    final years = {for (var y = 2025; y <= 2030; y++) y, _year}.toList()..sort();
    return years;
  }

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  String get _composedDate {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = int.tryParse(_day.text.trim()) ?? 1;
    return '$_year-${two(_month)}-${two(day)}';
  }

  @override
  void dispose() {
    _bookNumber.dispose();
    _summary.dispose();
    _summaryFocus.dispose();
    _day.dispose();
    super.dispose();
  }

  /// Year and month are picked, the day is typed — faster than a calendar for
  /// records that are entered in bulk.
  Widget _dateFields() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _dropdown(
              'السنة',
              '$_year',
              [for (final y in _years) '$y'],
              (v) => setState(() => _year = int.tryParse(v ?? '') ?? _year),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dropdown(
              'الشهر',
              '$_month',
              [for (var m = 1; m <= 12; m++) '$m'],
              (v) => setState(() {
                _month = int.tryParse(v ?? '') ?? _month;
                // Re-check the day against the new month's length.
                _formKey.currentState?.validate();
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _day,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'اليوم'),
              validator: (v) {
                final day = int.tryParse((v ?? '').trim());
                if (day == null) return 'مطلوب';
                if (day < 1 || day > _daysInMonth) return 'من 1 إلى $_daysInMonth';
                return null;
              },
            ),
          ),
        ],
      );

  /// A new document starts with the searchable lists empty, so typing in them
  /// filters straight away instead of first having to clear a preset value.
  void _initSelections(List<String> bookTypes, List<String> entities) {
    if (_initialized) return;
    final doc = widget.document;
    _bookType = doc != null && bookTypes.contains(doc.bookType) ? doc.bookType : null;
    // An edited document keeps its own party even if it left the option list.
    _requester = doc != null && doc.requester.isNotEmpty ? doc.requester : null;
    _initialized = true;
  }

  /// Switching the direction swaps the party list, so the selection has to
  /// follow it (the old choice is kept only when the new list contains it).
  void _changeDirection(String? value, List<String> nextEntities) {
    setState(() {
      _direction = value ?? kOutgoing;
      if (_requester != null && !nextEntities.contains(_requester)) _requester = null;
    });
    // The series follows the direction too: an incoming book never carries a
    // prefix, whatever the party was.
    if (!widget.isEdit) _suggestNumber();
  }

  /// Picking the party can move the book into another numbering series.
  void _changeParty(String? value) {
    setState(() => _requester = value);
    if (!widget.isEdit) _suggestNumber();
  }

  Future<void> _pickAttachment() async {
    if (!_isMobile) {
      await _pickFile();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('الكاميرا'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('المعرض'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('ملف (PDF / Word / Excel)'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'file') {
      await _pickFile();
      return;
    }
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      // Resized natively by the picker: decoding a full-size photo in Dart is
      // the slowest part of scanning.
      maxWidth: kScanWorkingSide.toDouble(),
      maxHeight: kScanWorkingSide.toDouble(),
      imageQuality: 95,
    );
    if (file != null && mounted) await _scanAndAttach(file.path);
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: 'ملفات', extensions: _attachmentExtensions)],
    );
    if (file != null) await _scanAndAttach(file.path);
  }

  /// Images go through the scanner preview first; other files attach directly.
  Future<void> _scanAndAttach(String sourcePath) async {
    final attachment = await runScanFlow(context, sourcePath);
    if (attachment != null && mounted) setState(() => _pickedAttachment = attachment);
  }

  /// Saves the form. With [addAnother], a new document stays open for the
  /// next entry instead of closing: the date, direction, type and party are
  /// kept (batches usually share them) and the book number moves on.
  Future<void> _save({bool addAnother = false}) async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_bookType == null || _requester == null) {
      _snack('يرجى اختيار نوع الكتاب و${entityLabel(_direction)}');
      return;
    }
    if (!await _confirmDuplicate()) return;
    setState(() => _saving = true);
    final draft = DocumentDraft(
      bookNumber: _bookNumber.text.trim(),
      datetime: _composedDate,
      bookType: _bookType!,
      requester: _requester!,
      status: _status,
      direction: _direction,
      summary: _summary.text.trim(),
    );
    final controller = ref.read(documentsControllerProvider);
    try {
      if (widget.isEdit) {
        await controller.edit(widget.document!, draft, newSourceAttachmentPath: _pickedAttachment);
      } else {
        await controller.create(draft, sourceAttachmentPath: _pickedAttachment);
      }
      if (!mounted) return;
      if (addAnother && !widget.isEdit) {
        _snack('تم حفظ الطلب ${draft.bookNumber}');
        _summary.clear();
        _bookNumber.clear();
        setState(() {
          _pickedAttachment = null;
          _saving = false;
        });
        // The party is kept for the next entry, so the series is kept with it.
        await _suggestNumber();
        _summaryFocus.requestFocus();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _saving = false);
      _snack('خطأ: $e');
    }
  }

  /// Warns before saving a book number that already exists for the same year
  /// and direction (numbers restart each year and differ per direction).
  Future<bool> _confirmDuplicate() async {
    final number = _bookNumber.text.trim();
    if (number.isEmpty) return true;
    List<Document> docs;
    try {
      docs = await ref.read(documentsProvider.future);
    } catch (_) {
      return true; // offline with no cache: nothing to compare against
    }
    if (!mounted) return false;
    final year = '$_year';
    final clash = docs.where((d) =>
        d.id != widget.document?.id &&
        d.bookNumber == number &&
        d.direction == _direction &&
        d.datetime.startsWith(year));
    if (clash.isEmpty) return true;
    final other = clash.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رقم مكرر'),
        content: Text(
          'يوجد كتاب $_direction برقم $number في سنة $year:\n«${other.summary}»\n\nهل تريد الحفظ على أي حال؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    return ok == true;
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final bookTypesAsync = ref.watch(optionValuesProvider('book_type'));
    final requestersAsync = ref.watch(optionValuesProvider('requester'));
    final recipientsAsync = ref.watch(optionValuesProvider('recipient'));
    final statusesAsync = ref.watch(optionValuesProvider('status'));

    final loading = bookTypesAsync.isLoading ||
        requestersAsync.isLoading ||
        recipientsAsync.isLoading ||
        statusesAsync.isLoading;
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.isEdit ? 'تعديل طلب' : 'إضافة طلب جديد')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bookTypes = bookTypesAsync.value ?? const [];
    final requesters = requestersAsync.value ?? const [];
    final serverRecipients = recipientsAsync.value ?? const [];
    final recipients = serverRecipients.isNotEmpty ? serverRecipients : kDefaultRecipients;
    final statuses = statusesAsync.value ?? const [];

    List<String> entitiesFor(String direction) => direction == kOutgoing ? recipients : requesters;
    final entities = entitiesFor(_direction);
    _initSelections(bookTypes, entities);

    final page = Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'تعديل طلب' : 'إضافة طلب جديد')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Direction comes first: it decides which party list follows.
                _dropdown('نوع الحركة', _direction, kDirections,
                    (v) => _changeDirection(v, entitiesFor(v ?? kOutgoing))),
                const SizedBox(height: 14),
                // The party comes before the number: it decides the series the
                // number belongs to (الوزارة -> M-13).
                _searchableDropdown(
                  entityLabel(_direction),
                  _requester,
                  // Keep an edited document's party even if it is off the list.
                  [
                    ...entities,
                    if (_requester != null && _requester!.isNotEmpty && !entities.contains(_requester))
                      _requester!,
                  ],
                  _changeParty,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bookNumber,
                  decoration: InputDecoration(
                    labelText: 'رقم الكتاب',
                    helperText: _numberPrefix.isEmpty
                        ? null
                        : 'كتب ${_requester ?? ''} لها تسلسل خاص ببادئة $_numberPrefix',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    if (int.tryParse(t) != null) return null;
                    if (seriesNumber(t, _numberPrefix) != null) return null;
                    return _numberPrefix.isEmpty
                        ? 'أرقام فقط'
                        : 'أرقام، أو $_numberPrefix متبوعة بأرقام';
                  },
                ),
                const SizedBox(height: 14),
                _dateFields(),
                const SizedBox(height: 14),
                _searchableDropdown(
                    'نوع الكتاب', _bookType, bookTypes, (v) => setState(() => _bookType = v)),
                const SizedBox(height: 14),
                _searchableDropdown('حالة الكتاب', statuses.contains(_status) ? _status : null,
                    statuses, (v) => setState(() => _status = v ?? _defaultStatus)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _summary,
                  focusNode: _summaryFocus,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'ملخص الكتاب', alignLabelWithHint: true),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 20),
                Text('الملف المرفق', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _attachmentArea(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(widget.isEdit ? 'حفظ التعديلات' : 'حفظ الطلب'),
                ),
                if (!widget.isEdit) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('حفظ وإضافة طلب آخر'),
                  ),
                ],
                if (!_isMobile) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.isEdit
                        ? 'اختصار: Ctrl+S للحفظ'
                        : 'اختصارات: Ctrl+S للحفظ · Ctrl+Enter للحفظ وإضافة طلب آخر',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // Desktop entry is keyboard driven: Ctrl+S saves, Ctrl+Enter saves and
    // opens a blank form for the next document.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        if (!widget.isEdit)
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _save(addAnother: true),
      },
      child: Focus(autofocus: true, child: page),
    );
  }

  Widget _dropdown(String label, String? value, List<String> options, ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: onChanged,
      );

  /// Same role as [_dropdown], but the field takes typing and narrows the menu
  /// as you go — used for the long lookup lists.
  Widget _searchableDropdown(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) =>
      DropdownMenu<String>(
        // A new key rebuilds the field when the list or the value is swapped
        // from outside (changing the direction replaces the party list).
        key: ValueKey('$label|$value|${options.length}'),
        initialSelection: value,
        label: Text(label),
        expandedInsets: EdgeInsets.zero,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 320,
        inputDecorationTheme: Theme.of(context).inputDecorationTheme,
        dropdownMenuEntries: [for (final o in options) DropdownMenuEntry(value: o, label: o)],
        onSelected: onChanged,
      );

  Widget _attachmentArea() {
    final theme = Theme.of(context);
    final previewPath = _pickedAttachment ??
        (widget.document?.hasAttachment == true ? widget.document!.attachmentPath : null);
    final isImage = previewPath != null && _imageExt.contains(p.extension(previewPath).toLowerCase());

    final box = Container(
      height: 170,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _dragging ? theme.colorScheme.primary : theme.colorScheme.secondary,
          width: _dragging ? 2.5 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: previewPath == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_file, size: 36, color: theme.hintColor),
                  const SizedBox(height: 8),
                  Text(
                    _isMobile ? 'اضغط لاختيار ملف' : 'اسحب الملف هنا أو اضغط للاختيار',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            )
          : isImage
              ? Image.file(File(previewPath), fit: BoxFit.contain, width: double.infinity)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 40),
                      const SizedBox(height: 8),
                      Text(p.basename(previewPath)),
                    ],
                  ),
                ),
    );

    final tappable = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickAttachment,
      child: box,
    );

    if (_isMobile) return tappable;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        if (detail.files.isEmpty) return;
        final path = detail.files.first.path;
        final ext = p.extension(path).toLowerCase().replaceAll('.', '');
        if (_attachmentExtensions.contains(ext)) {
          _scanAndAttach(path);
        } else {
          _snack('نوع الملف غير مدعوم');
        }
      },
      child: tappable,
    );
  }
}
