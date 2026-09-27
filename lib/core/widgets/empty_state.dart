import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Friendly, animated empty-state used across list/grid screens.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: theme.hintColor),
          const SizedBox(height: 12),
          Text(text, style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor)),
        ],
      )
          .animate()
          .fadeIn(duration: 320.ms)
          .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), curve: Curves.easeOutBack),
    );
  }
}
