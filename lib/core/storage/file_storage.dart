import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles copying attachments into the app's own storage, organised on disk.
///
/// Task images live under `data/tasks/<entity>/`, mirroring the folder-per-entity
/// model shown in the UI. Document attachments live under `data/attachments/`.
class FileStorage {
  static const imageExtensions = {'.png', '.jpg', '.jpeg'};

  Future<Directory> _dataDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'data'));
    await dir.create(recursive: true);
    return dir;
  }

  String _sanitize(String name) {
    const invalid = r'<>:"/\|?*';
    final cleaned = name.trim().split('').map((c) => invalid.contains(c) ? '_' : c).join();
    final trimmed = cleaned.replaceAll(RegExp(r'[ .]+$'), '');
    return trimmed.isEmpty ? 'غير محدد' : trimmed;
  }

  String _uniqueName(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16);
    return '$stamp$rand$ext';
  }

  /// Copies a document attachment (image or office/pdf file) into storage.
  Future<String> saveDocumentAttachment(String sourcePath) async {
    final base = await _dataDir();
    final dir = Directory(p.join(base.path, 'attachments'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, _uniqueName(sourcePath));
    await File(sourcePath).copy(target);
    return target;
  }

  Future<String> saveTaskImage(String sourcePath, String entity) async {
    final base = await _dataDir();
    final dir = Directory(p.join(base.path, 'tasks', _sanitize(entity)));
    await dir.create(recursive: true);
    final target = p.join(dir.path, _uniqueName(sourcePath));
    await File(sourcePath).copy(target);
    return target;
  }

  /// Moves an existing task attachment into another entity's folder.
  Future<String> moveTaskImage(String currentPath, String entity) async {
    final source = File(currentPath);
    if (!await source.exists()) return currentPath;
    final base = await _dataDir();
    final dir = Directory(p.join(base.path, 'tasks', _sanitize(entity)));
    await dir.create(recursive: true);
    var target = p.join(dir.path, p.basename(currentPath));
    if (p.equals(target, currentPath)) return currentPath;
    if (await File(target).exists()) {
      target = p.join(dir.path, _uniqueName(currentPath));
    }
    await source.rename(target);
    return target;
  }

  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static bool isImage(String path) => imageExtensions.contains(p.extension(path).toLowerCase());
}

final fileStorageProvider = Provider<FileStorage>((ref) => FileStorage());
