import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/sort_bar.dart';
import '../controller/tasks_controller.dart';
import '../model/task.dart';
import 'widgets/folder_card.dart';
import 'widgets/task_card.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(Task task) async {
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
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المهمات'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-tasks',
        onPressed: () => context.push('/task-form'),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مهمة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'البحث برقم المهمة',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (tasks) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: KeyedSubtree(
                  key: ValueKey(_query.isEmpty),
                  child: _query.isEmpty ? _folders(context) : _searchResults(context, tasks),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folders(BuildContext context) {
    final folders = ref.watch(taskFoldersProvider);
    if (folders.isEmpty) {
      return const EmptyState(icon: Icons.folder_open_outlined, text: 'لا توجد مهمات بعد');
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.gridColumns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
      ),
      itemCount: folders.length,
      itemBuilder: (_, i) => FolderCard(
        folder: folders[i],
        onTap: () => context.push('/tasks/folder/${Uri.encodeComponent(folders[i].entity)}'),
      )
          .animate()
          .fadeIn(duration: 260.ms, delay: (30 * (i % 12)).ms)
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
    );
  }

  Widget _searchResults(BuildContext context, List<Task> tasks) {
    final sort = ref.watch(taskSortProvider);
    final results = applySort(
      tasks.where((t) => t.taskNumber == _query).toList(),
      sort,
      numberOf: (t) => t.taskNumber,
      dateOf: (t) => t.createdAt,
    );
    if (results.isEmpty) {
      return const EmptyState(icon: Icons.search_off_outlined, text: 'لا توجد مهمة بهذا الرقم');
    }
    return Column(
      children: [
        SortBar(
          state: sort,
          onFieldChanged: (f) => ref.read(taskSortProvider.notifier).state = sort.withField(f),
          onToggleDirection: () => ref.read(taskSortProvider.notifier).state = sort.toggleDirection(),
        ),
        Expanded(
          child: _TaskGrid(
            tasks: results,
            onEdit: (t) => context.push('/task-form', extra: t),
            onDelete: _confirmDelete,
          ),
        ),
      ],
    );
  }
}

class _TaskGrid extends StatelessWidget {
  const _TaskGrid({required this.tasks, required this.onEdit, required this.onDelete});

  final List<Task> tasks;
  final ValueChanged<Task> onEdit;
  final ValueChanged<Task> onDelete;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.gridColumns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: tasks.length,
      itemBuilder: (_, i) => TaskCard(
        task: tasks[i],
        onEdit: () => onEdit(tasks[i]),
        onDelete: () => onDelete(tasks[i]),
      )
          .animate()
          .fadeIn(duration: 260.ms, delay: (30 * (i % 12)).ms)
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
    );
  }
}

/// Shared grid used by the folder page too.
class TaskGrid extends StatelessWidget {
  const TaskGrid({super.key, required this.tasks, required this.onEdit, required this.onDelete});

  final List<Task> tasks;
  final ValueChanged<Task> onEdit;
  final ValueChanged<Task> onDelete;

  @override
  Widget build(BuildContext context) =>
      _TaskGrid(tasks: tasks, onEdit: onEdit, onDelete: onDelete);
}
