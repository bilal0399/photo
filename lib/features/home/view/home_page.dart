import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _emblem(theme)
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  _header(theme)
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 150.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                  const SizedBox(height: 40),
                  _quickActions(context)
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 300.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emblem(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.asset(
          'assets/images/home_logo.png',
          width: 168,
          height: 168,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Column(
      children: [
        Text(
          'الجمهورية العربية السورية',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'وزارة الدفاع',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5)),
          ),
          child: Text(
            'ديوان الفرقة 42',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.note_add_outlined,
        label: 'إضافة طلب',
        color: AppColors.primary,
        onTap: () => context.push('/document-form'),
      ),
      _QuickAction(
        icon: Icons.create_new_folder_outlined,
        label: 'إضافة مهمة',
        color: AppColors.secondaryHover,
        onTap: () => context.push('/task-form'),
      ),
    ];

    if (context.isMobile) {
      return Column(
        children: [
          for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 14), child: a),
        ],
      );
    }
    return Row(
      children: [
        for (final a in actions) Expanded(child: Padding(padding: const EdgeInsets.all(7), child: a)),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
