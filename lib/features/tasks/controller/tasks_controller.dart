import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/sort_bar.dart';
import '../model/task.dart';
import '../service/tasks_service.dart';

/// Current sort choice shared by the task folder view and search results.
final taskSortProvider = StateProvider<SortState>((_) => const SortState(SortField.date));

/// Owns the Tasks list state and exposes intent methods to the views.
/// Views watch [tasksControllerProvider]; folder/search groupings are derived
/// from the loaded list by the sibling providers below.
class TasksController extends AsyncNotifier<List<Task>> {
  TasksService get _service => ref.read(tasksServiceProvider);

  @override
  Future<List<Task>> build() => _service.all();

  Future<void> _reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.all);
  }

  Future<String> nextNumber() async {
    final tasks = state.valueOrNull ?? await _service.all();
    var max = 0;
    for (final t in tasks) {
      final n = int.tryParse(t.taskNumber);
      if (n != null && n > max) max = n;
    }
    return '${max + 1}';
  }

  Future<void> create({
    required String taskNumber,
    required String entity,
    String? sourceImagePath,
  }) async {
    await _service.create(taskNumber: taskNumber, entity: entity, sourceImagePath: sourceImagePath);
    await _reload();
  }

  Future<void> edit(
    Task task, {
    required String taskNumber,
    required String entity,
    String? newSourceImagePath,
  }) async {
    await _service.edit(task,
        taskNumber: taskNumber, entity: entity, newSourceImagePath: newSourceImagePath);
    await _reload();
  }

  Future<void> remove(Task task, {bool deleteFile = true}) async {
    await _service.remove(task, deleteFile: deleteFile);
    await _reload();
  }
}

final tasksControllerProvider =
    AsyncNotifierProvider<TasksController, List<Task>>(TasksController.new);

/// Folder list (entity + count) derived from the loaded tasks.
final taskFoldersProvider = Provider<List<TaskFolder>>((ref) {
  final tasks = ref.watch(tasksControllerProvider).valueOrNull ?? const [];
  final counts = <String, int>{};
  for (final t in tasks) {
    counts[t.entity] = (counts[t.entity] ?? 0) + 1;
  }
  return counts.entries.map((e) => TaskFolder(entity: e.key, count: e.value)).toList();
});
