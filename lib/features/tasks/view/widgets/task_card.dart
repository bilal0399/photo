import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/image_viewer.dart';
import '../../model/task.dart';
import '../../service/tasks_service.dart';
import 'task_image.dart';

class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Object get _heroTag => 'task-image-${task.id}';

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (!task.hasAttachment) return;
    final url = await ref.read(taskAttachmentUrlProvider(task.attachmentPath).future);
    if (url == null || !context.mounted) return;
    await showNetworkImageViewer(context, url, heroTag: _heroTag);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'مهمة ${task.taskNumber}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: task.hasAttachment
                    ? Hero(tag: _heroTag, child: TaskImage(path: task.attachmentPath))
                    : Center(
                        child: Icon(Icons.image_outlined, color: theme.hintColor, size: 34),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                task.entity,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
