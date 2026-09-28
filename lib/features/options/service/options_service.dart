import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../model/option_item.dart';

/// Contract for reading lookup lists (book types, requesters, statuses).
/// These now come from the server and are read-only in the app.
abstract class OptionsService {
  Future<List<OptionItem>> byCategory(String category);
}

/// Reads options from Supabase.
class SupabaseOptionsService implements OptionsService {
  SupabaseOptionsService(this._client);

  final SupabaseClient _client;

  @override
  Future<List<OptionItem>> byCategory(String category) async {
    final rows = await _client
        .from('options')
        .select('value')
        .eq('category', category)
        .order('sort_order')
        .order('value');
    return [
      for (final r in rows as List)
        OptionItem(category: category, value: r['value'] as String, createdAt: ''),
    ];
  }
}

/// Online-first with a local cache: fetches from [remote] and mirrors into
/// sqflite; when offline, serves the last cached values so dropdowns still work.
class CachedOptionsService implements OptionsService {
  CachedOptionsService(this.remote, this._db);

  final OptionsService remote;
  final AppDatabase _db;

  @override
  Future<List<OptionItem>> byCategory(String category) async {
    try {
      final items = await remote.byCategory(category);
      final db = await _db.database;
      final now = DateTime.now().toIso8601String();
      // One transaction: a failure mid-way keeps the previous values cached.
      await db.transaction((txn) async {
        await txn.delete('options', where: 'category = ?', whereArgs: [category]);
        final batch = txn.batch();
        for (final it in items) {
          batch.insert('options', {'category': category, 'value': it.value, 'created_at': now});
        }
        await batch.commit(noResult: true);
      });
      return items;
    } catch (_) {
      final db = await _db.database;
      final rows = await db.query('options',
          where: 'category = ?', whereArgs: [category], orderBy: 'value COLLATE NOCASE');
      return rows.map(OptionItem.fromMap).toList();
    }
  }
}

final optionsServiceProvider = Provider<OptionsService>(
  (ref) => CachedOptionsService(
    SupabaseOptionsService(Supabase.instance.client),
    ref.watch(appDatabaseProvider),
  ),
);

/// The plain string values for a category (used by dropdowns).
final optionValuesProvider = FutureProvider.family<List<String>, String>((ref, category) async {
  final items = await ref.watch(optionsServiceProvider).byCategory(category);
  return items.map((e) => e.value).toList();
});
