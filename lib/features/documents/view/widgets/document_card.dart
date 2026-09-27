import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../model/document.dart';

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Document document;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color _statusColor() => switch (document.status) {
        'قيد المراجعة' => AppColors.secondary,
        'تمت الموافقة' => AppColors.primary,
        'مرفوض' => AppColors.danger,
        'تقييم' => AppColors.warning,
        _ => const Color(0xFF475467),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = document.bookNumber.isNotEmpty ? document.bookNumber : '#${document.id}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(number,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor(),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(document.status,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
              const SizedBox(height: 6),
              Text(document.dateOnly,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(document.requester,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(document.bookType, style: theme.textTheme.bodyMedium),
                    Text(document.direction, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
