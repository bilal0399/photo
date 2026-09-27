import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../service/settings_service.dart';

/// Holds the active [ThemeMode], loads the saved value on start and persists
/// changes. The app root watches [themeModeProvider].
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final value = await ref.read(settingsServiceProvider).get('theme');
    if (value != null) state = _parse(value);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsServiceProvider).set('theme', mode.name);
  }

  ThemeMode _parse(String value) => switch (value.toLowerCase()) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeProvider = NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
