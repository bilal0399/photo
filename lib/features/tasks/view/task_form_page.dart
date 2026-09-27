import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/scanner/scan_flow.dart';
import '../../options/service/options_service.dart';
import '../controller/tasks_controller.dart';
import '../model/task.dart';

const _otherOption = 'أخرى';

class TaskFormPage extends ConsumerStatefulWidget {
  const TaskFormPage({super.key, this.task});

  final Task? task;

  bool get isEdit => task != null;

  @override
  ConsumerState<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends ConsumerState<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _otherEntityController = TextEditingController();

  String? _entitySelection;
  String? _pickedImagePath;
  bool _dragging = false;
  bool _saving = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    if (task != null) {
      _numberController.text = task.taskNumber;
    } else {
      ref.read(tasksControllerProvider.notifier).nextNumber().then((n) {
        if (mounted && _numberController.text.isEmpty) _numberController.text = n;
      });
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _otherEntityController.dispose();
    super.dispose();
  }

  /// Once options load, pick the initial dropdown value for an edited task.
  void _syncEntitySelection(List<String> options) {
    if (_entitySelection != null) return;
    final task = widget.task;
    if (task == null) {
      _entitySelection = options.isNotEmpty ? options.first : _otherOption;
    } else if (options.contains(task.entity)) {
      _entitySelection = task.entity;
    } else {
      _entitySelection = _otherOption;
      _otherEntityController.text = task.entity;
    }
  }

  String get _resolvedEntity =>
      _entitySelection == _otherOption ? _otherEntityController.text.trim() : (_entitySelection ?? '');

  Future<void> _pickFromFiles() async {
    const group = fs.XTypeGroup(label: 'صور', extensions: ['png', 'jpg', 'jpeg']);
    final file = await fs.openFile(acceptedTypeGroups: [group]);
    if (file != null) await _scanAndAttach(file.path);
  }

  /// Runs the picked image through the scanner preview before attaching it.
  Future<void> _scanAndAttach(String sourcePath) async {
    final scanned = await runScanFlow(context, sourcePath);
    if (scanned != null && mounted) setState(() => _pickedImagePath = scanned);
  }

  Future<void> _pickFromCameraOrGallery() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('الكاميرا'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('المعرض'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      // Resized natively by the picker: decoding a full-size photo in Dart is
      // the slowest part of scanning.
      maxWidth: kScanWorkingSide.toDouble(),
      maxHeight: kScanWorkingSide.toDouble(),
      imageQuality: 95,
    );
    if (file != null && mounted) await _scanAndAttach(file.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final entity = _resolvedEntity;
    if (entity.isEmpty) {
      _snack('يرجى تحديد جهة المهمة');
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(tasksControllerProvider.notifier);
    try {
      if (widget.isEdit) {
        await controller.edit(
          widget.task!,
          taskNumber: _numberController.text.trim(),
          entity: entity,
          newSourceImagePath: _pickedImagePath,
        );
      } else {
        await controller.create(
          taskNumber: _numberController.text.trim(),
          entity: entity,
          sourceImagePath: _pickedImagePath,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _saving = false);
      _snack('خطأ: $e');
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final optionsAsync = ref.watch(optionValuesProvider('requester'));

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'تعديل مهمة' : 'إضافة مهمة جديدة')),
      body: optionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (options) {
          _syncEntitySelection(options);
          final items = [...options, _otherOption];
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextFormField(
                      controller: _numberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'رقم المهمة'),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isNotEmpty && int.tryParse(t) == null) return 'أرقام فقط';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _entitySelection,
                      decoration: const InputDecoration(labelText: 'جهة المهمة'),
                      items: [
                        for (final o in items) DropdownMenuItem(value: o, child: Text(o)),
                      ],
                      onChanged: (v) => setState(() => _entitySelection = v),
                    ),
                    if (_entitySelection == _otherOption) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otherEntityController,
                        decoration: const InputDecoration(labelText: 'اكتب جهة المهمة'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text('صورة المهمة', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _imageArea(),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(widget.isEdit ? 'حفظ التعديلات' : 'حفظ المهمة'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _imageArea() {
    final theme = Theme.of(context);
    final previewPath = _pickedImagePath ??
        (widget.task?.hasAttachment == true ? widget.task!.attachmentPath : null);

    Widget box = Container(
      height: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _dragging ? theme.colorScheme.primary : theme.colorScheme.secondary,
          width: _dragging ? 2.5 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: previewPath != null
          ? Image.file(File(previewPath), fit: BoxFit.contain, width: double.infinity)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 40, color: theme.hintColor),
                  const SizedBox(height: 8),
                  Text(
                    _isMobile ? 'اضغط لاختيار صورة' : 'اسحب الصورة هنا أو اضغط للاختيار',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
    );

    final tappable = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _isMobile ? _pickFromCameraOrGallery : _pickFromFiles,
      child: box,
    );

    if (_isMobile) return tappable;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        if (detail.files.isNotEmpty) {
          final path = detail.files.first.path;
          final ext = path.toLowerCase();
          if (ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
            _scanAndAttach(path);
          } else {
            _snack('الملف يجب أن يكون صورة (png, jpg, jpeg)');
          }
        }
      },
      child: tappable,
    );
  }
}
