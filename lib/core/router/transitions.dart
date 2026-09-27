import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A gentle slide-up + fade transition used for pushed pages (forms, details,
/// folder drill-downs). Gives the app a modern, mobile-native feel.
CustomTransitionPage<T> slideFadePage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.045), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
