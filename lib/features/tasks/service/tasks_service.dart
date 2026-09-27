import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../model/task.dart';

/// Contract for the Tasks feature. The whole list is loaded and grouped/filtered
/// client-side, which keeps the offline cache trivial.
abstract class TasksService {
  Future<List<Task>> all();
  Future<void> create({required String taskNumber, required String entity, String? sourceImagePath});
  Future<void> edit(Task task,
      {required String taskNumber, required String entity, String? newSourceImagePath});
  Future<void> remove(Task task, {required bool deleteFile});

  Future<String?> attachmentUrl(String path);
  Future<Uint8List?> attachmentBytes(String path);
}

class SupabaseTasksService implements TasksService {
  SupabaseTasksService(this._client);

  final SupabaseClient _client;
  static const _bucket = 'tasks';

  Task _fromRow(Map<String, dynamic> r) => Task(
        id: r['id'] as String?,
        taskNumber: (r['task_number'] as String?) ?? '',
        entity: (r['entity'] as String?) ?? '',
        attachmentPath: (r['attachment_path'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
        updatedAt: r['updated_at'] as String?,
      );

  Future<String> _upload(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final ext = p.extension(sourcePath).toLowerCase();
    final object = 'uploads/${DateTime.now().millisecondsSinceEpoch}'
        '${Random().nextInt(0xFFFFFF).toRadixString(16)}$ext';
    await _client.storage.from(_bucket).uploadBinary(object, bytes);
    return object;
  }

  /// Best-effort removal of a storage object that no record points at.
  Future<void> _removeObject(String path) async {
    if (path.isEmpty) return;
    try {
      await _client.storage.from(_bucket).remove([path]);
    } catch (e) {
      debugPrint('Could not remove attachment $path: $e');
    }
  }

  @override
  Future<List<Task>> all() async {
    final rows = await _client.from('tasks').select().order('created_at', ascending: false);
    return [for (final r in rows as List) _fromRow(r as Map<String, dynamic>)];
  }

  @override
  Future<void> create({required String taskNumber, required String entity, String? sourceImagePath}) async {
    var attachment = '';
    if (sourceImagePath != null && sourceImagePath.isNotEmpty) {
      attachment = await _upload(sourceImagePath);
    }
    try {
      await _client.from('tasks').insert({
        'task_number': taskNumber,
        'entity': entity,
        'attachment_path': attachment,
      });
    } catch (_) {
      await _removeObject(attachment); // don't leave an orphaned upload behind
      rethrow;
    }
  }

  @override
  Future<void> edit(Task task,
      {required String taskNumber, required String entity, String? newSourceImagePath}) async {
    final previous = task.attachmentPath;
    var attachment = previous;
    if (newSourceImagePath != null && newSourceImagePath.isNotEmpty) {
      attachment = await _upload(newSourceImagePath);
    }
    try {
      await _client.from('tasks').update({
        'task_number': taskNumber,
        'entity': entity,
        'attachment_path': attachment,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', task.id!);
    } catch (_) {
      if (attachment != previous) await _removeObject(attachment);
      rethrow;
    }
    // Only drop the old object once the record points at the new one.
    if (attachment != previous) await _removeObject(previous);
  }

  @override
  Future<void> remove(Task task, {required bool deleteFile}) async {
    await _client.from('tasks').delete().eq('id', task.id!);
    if (deleteFile) await _removeObject(task.attachmentPath);
  }

  @override
  Future<String?> attachmentUrl(String path) async {
    if (path.isEmpty) return null;
    try {
      return await _client.storage.from(_bucket).createSignedUrl(path, _signedUrlLifetime.inSeconds);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> attachmentBytes(String path) async {
    if (path.isEmpty) return null;
    try {
      return await _client.storage.from(_bucket).download(path);
    } catch (_) {
      return null;
    }
  }
}

/// Online-first with a local mirror for offline reads.
class CachedTasksService implements TasksService {
  CachedTasksService(this.remote, this._db);

  final TasksService remote;
  final AppDatabase _db;

  @override
  Future<List<Task>> all() async {
    try {
      final tasks = await remote.all();
      final db = await _db.database;
      // One transaction: a failure mid-way keeps the previous cache intact
      // instead of leaving it empty.
      await db.transaction((txn) async {
        await txn.delete('tasks');
        final batch = txn.batch();
        for (final t in tasks) {
          batch.insert('tasks', t.toCache());
        }
        await batch.commit(noResult: true);
      });
      return tasks;
    } catch (_) {
      final db = await _db.database;
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      return rows.map(Task.fromMap).toList();
    }
  }

  @override
  Future<void> create({required String taskNumber, required String entity, String? sourceImagePath}) =>
      remote.create(taskNumber: taskNumber, entity: entity, sourceImagePath: sourceImagePath);

  @override
  Future<void> edit(Task task,
          {required String taskNumber, required String entity, String? newSourceImagePath}) =>
      remote.edit(task, taskNumber: taskNumber, entity: entity, newSourceImagePath: newSourceImagePath);

  @override
  Future<void> remove(Task task, {required bool deleteFile}) =>
      remote.remove(task, deleteFile: deleteFile);

  @override
  Future<String?> attachmentUrl(String path) => remote.attachmentUrl(path);

  @override
  Future<Uint8List?> attachmentBytes(String path) => remote.attachmentBytes(path);
}

final tasksServiceProvider = Provider<TasksService>(
  (ref) => CachedTasksService(
    SupabaseTasksService(Supabase.instance.client),
    ref.watch(appDatabaseProvider),
  ),
);

/// Signed URLs are issued for this long by [SupabaseTasksService].
const _signedUrlLifetime = Duration(hours: 1);

/// Signed URL for a task attachment.
///
/// Dropped once no widget shows it, and re-issued a few minutes before it
/// expires so an image that stays on screen never turns into a broken link.
final taskAttachmentUrlProvider = FutureProvider.autoDispose.family<String?, String>((ref, path) {
  final refresh = Timer(_signedUrlLifetime - const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  return ref.watch(tasksServiceProvider).attachmentUrl(path);
});
