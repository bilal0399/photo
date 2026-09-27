import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/sort_bar.dart';
import '../controller/tasks_controller.dart';
import '../model/task.dart';
import 'tasks_page.dart' show TaskGrid;

class TaskFolderPage extends ConsumerWidget {
  const TaskFolderPage({super.key, required this.entity});

  final String entity;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Task task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذه المهمة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(tasksControllerProvider.notifier).remove(task);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(taskSortProvider);
    final tasks = applySort(
      (ref.watch(tasksControllerProvider).valueOrNull ?? const <Task>[])
          .where((t) => t.entity == entity)
          .toList(),
      sort,
      numberOf: (t) => t.taskNumber,
      dateOf: (t) => t.createdAt,
    );

    return Scaffold(
      appBar: AppBar(title: Text(entity), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-task-folder',
        onPressed: () => context.push('/task-form'),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مهمة'),
      ),
      body: tasks.isEmpty
          ? const EmptyState(icon: Icons.folder_open_outlined, text: 'لا توجد مهمات في هذا المجلد')
          : Column(
              children: [
                SortBar(
                  state: sort,
                  onFieldChanged: (f) =>
                      ref.read(taskSortProvider.notifier).state = sort.withField(f),
                  onToggleDirection: () =>
                      ref.read(taskSortProvider.notifier).state = sort.toggleDirection(),
                ),
                Expanded(
                  child: TaskGrid(
                    tasks: tasks,
                    onEdit: (t) => context.push('/task-form', extra: t),
                    onDelete: (t) => _confirmDelete(context, ref, t),
                  ),
                ),
              ],
            ),
    );
  }
}
