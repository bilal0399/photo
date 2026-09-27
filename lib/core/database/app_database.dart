import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens (and caches) the single local SQLite database shared by all features.
///
/// This is the only place that knows about sqflite. Features talk to their own
/// `Service` classes; those receive the [Database] from here. When a remote
/// backend (e.g. Supabase) is introduced later, features keep their Service
/// interface and only a different implementation is wired in — this class and
/// its provider stay untouched.
class AppDatabase {
  Database? _db;
  Future<Database>? _opening;

  static bool _ffiReady = false;
  static const int _version = 3;

  /// Caches the open Future so concurrent first callers share a single open
  /// (avoids re-initialising the sqflite factory repeatedly).
  Future<Database> get database {
    if (_db != null) return Future.value(_db!);
    return _opening ??= _open().then((db) {
      _db = db;
      _opening = null;
      return db;
    });
  }

  Future<Database> _open() async {
    if (!_ffiReady && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiReady = true;
    }
    final supportDir = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(supportDir.path, 'data'));
    await dataDir.create(recursive: true);
    final path = p.join(dataDir.path, 'archive.db');

    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  }

  /// The `documents` table doubles as the offline cache for the server rows,
  /// so its primary key is the server uuid (TEXT).
  static const _documentsTableSql = '''
    CREATE TABLE documents (
      id TEXT PRIMARY KEY,
      document_code TEXT,
      book_number TEXT,
      datetime TEXT,
      book_type TEXT,
      requester TEXT,
      status TEXT,
      direction TEXT,
      summary TEXT,
      attachment_path TEXT,
      approval_date TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''';

  /// The `tasks` table also doubles as the offline cache (server uuid PK).
  static const _tasksTableSql = '''
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      task_number TEXT,
      entity TEXT,
      attachment_path TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''';

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS documents');
      await db.execute(_documentsTableSql);
    }
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS tasks');
      await db.execute(_tasksTableSql);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_documentsTableSql);
    await db.execute(_tasksTableSql);
    await db.execute('''
      CREATE TABLE options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        value TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(category, value)
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await _seedDefaults(db);
  }

  Future<void> _seedDefaults(Database db) async {
    const defaults = <String, List<String>>{
      'book_type': ['طلب لوجستيات', 'طلب تقنيات', 'طلب مالي', 'طلب إداري'],
      'requester': ['فوج المدفعية', 'فوج الهندسة', 'الفرع المالي', 'الفرع التقني'],
      'status': ['قيد المراجعة', 'تمت الموافقة', 'مرفوض', 'تقييم'],
    };
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    defaults.forEach((category, values) {
      for (final value in values) {
        batch.insert('options', {
          'category': category,
          'value': value,
          'created_at': now,
        });
      }
    });
    batch.insert('settings', {'key': 'theme', 'value': 'system'});
    await batch.commit(noResult: true);
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
