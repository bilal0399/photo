import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/database/app_database.dart';

/// Key/value app settings (currently the theme mode).
abstract class SettingsService {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

class LocalSettingsService implements SettingsService {
  LocalSettingsService(this._db);

  final AppDatabase _db;

  @override
  Future<String?> get(String key) async {
    final db = await _db.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => LocalSettingsService(ref.watch(appDatabaseProvider)),
);
