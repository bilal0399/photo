import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/scanner/document_scanner.dart';
import '../model/document.dart';

/// Storage folder holding attachments that already went through the scanner.
/// The prefix doubles as the "already processed" marker, so a bulk run can
/// skip them without a schema change.
const kScannedPrefix = 'documents/scanned/';

bool isProcessedScan(String storagePath) => storagePath.startsWith(kScannedPrefix);

/// Contract for the Documents feature. The list is loaded whole and filtered
/// client-side (147 rows — trivial), which keeps the offline cache simple.
abstract class DocumentsService {
  Future<List<Document>> all();
  Future<void> create(DocumentDraft draft, {String? sourceAttachmentPath});
  Future<void> edit(Document doc, DocumentDraft draft, {String? newSourceAttachmentPath});
  Future<void> remove(Document doc, {required bool deleteFile});

  /// Points the record at a locally processed copy of its attachment and
  /// removes the object it replaces. Used by the scanner, which rewrites an
  /// attachment without touching any other field. Returns the new storage path.
  Future<String> replaceAttachment(Document doc, String localPath, {bool deleteOriginal});

  /// A signed, temporary URL to view an attachment stored in Supabase Storage.
  Future<String?> attachmentUrl(String path);

  /// Raw bytes of an attachment (for viewing/printing/opening locally).
  Future<Uint8List?> attachmentBytes(String path);
}

class SupabaseDocumentsService implements DocumentsService {
  SupabaseDocumentsService(this._client);

  final SupabaseClient _client;
  static const _bucket = 'attachments';

  String _today() => DateTime.now().toIso8601String().split('T').first;

  String _generateCode() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'D42-${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Document _fromRow(Map<String, dynamic> r) => Document(
        id: r['id'] as String?,
        documentCode: (r['document_code'] as String?) ?? '',
        bookNumber: (r['book_number'] as String?) ?? '',
        datetime: (r['doc_date'] as String?) ?? '',
        bookType: (r['book_type'] as String?) ?? '',
        requester: (r['requester'] as String?) ?? '',
        status: (r['status'] as String?) ?? '',
        direction: (r['direction'] as String?) ?? '',
        summary: (r['summary'] as String?) ?? '',
        attachmentPath: (r['attachment_path'] as String?) ?? '',
        approvalDate: (r['approval_date'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
        updatedAt: r['updated_at'] as String?,
      );

  /// Uploads an attachment and returns its storage path.
  ///
  /// Images are always stored cropped and enhanced: the form hands over the
  /// scanner's output, and any image that skipped the scanner is processed
  /// here automatically. Scans go under [kScannedPrefix] so a bulk run never
  /// processes them a second time.
  Future<String> _upload(String sourcePath) async {
    var bytes = await File(sourcePath).readAsBytes();
    var ext = p.extension(sourcePath).toLowerCase();
    var folder = 'documents/';
    if (isScannerOutput(sourcePath)) {
      folder = kScannedPrefix;
    } else if (isScannable(sourcePath)) {
      final scan = await scanBytes(bytes);
      if (scan != null) {
        bytes = scan.output.bytes;
        ext = scan.output.extension;
        folder = kScannedPrefix;
      }
    }
    final object = '$folder${DateTime.now().millisecondsSinceEpoch}'
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

  Map<String, dynamic> _payload(DocumentDraft d, String attachment, String? approval) => {
        'book_number': d.bookNumber,
        'doc_date': d.datetime.isEmpty ? null : d.datetime,
        'book_type': d.bookType,
        'requester': d.requester,
        'status': d.status,
        'direction': d.direction,
        'summary': d.summary,
        'attachment_path': attachment,
        'approval_date': approval,
      };

  @override
  Future<List<Document>> all() async {
    final rows = await _client.from('documents').select().order('doc_date', ascending: false);
    return [for (final r in rows as List) _fromRow(r as Map<String, dynamic>)];
  }

  @override
  Future<void> create(DocumentDraft draft, {String? sourceAttachmentPath}) async {
    var attachment = '';
    if (sourceAttachmentPath != null && sourceAttachmentPath.isNotEmpty) {
      attachment = await _upload(sourceAttachmentPath);
    }
    final approval = draft.status == kApprovedStatus ? _today() : null;
    try {
      await _client.from('documents').insert({
        'document_code': _generateCode(),
        ..._payload(draft, attachment, approval),
      });
    } catch (_) {
      await _removeObject(attachment); // don't leave an orphaned upload behind
      rethrow;
    }
  }

  @override
  Future<void> edit(Document doc, DocumentDraft draft, {String? newSourceAttachmentPath}) async {
    final previous = doc.attachmentPath;
    var attachment = previous;
    if (newSourceAttachmentPath != null && newSourceAttachmentPath.isNotEmpty) {
      attachment = await _upload(newSourceAttachmentPath);
    }
    final approval = draft.status == kApprovedStatus
        ? (doc.approvalDate.isNotEmpty ? doc.approvalDate : _today())
        : null;
    try {
      await _client.from('documents').update(_payload(draft, attachment, approval)).eq('id', doc.id!);
    } catch (_) {
      if (attachment != previous) await _removeObject(attachment);
      rethrow;
    }
    // Only drop the old object once the record points at the new one.
    if (attachment != previous) await _removeObject(previous);
  }

  @override
  Future<String> replaceAttachment(Document doc, String localPath,
      {bool deleteOriginal = true}) async {
    final bytes = await File(localPath).readAsBytes();
    final ext = p.extension(localPath).toLowerCase();
    final object = '$kScannedPrefix${DateTime.now().millisecondsSinceEpoch}'
        '${Random().nextInt(0xFFFFFF).toRadixString(16)}$ext';
    await _client.storage.from(_bucket).uploadBinary(object, bytes);
    // Only drop the old object once the record points at the new one.
    await _client.from('documents').update({'attachment_path': object}).eq('id', doc.id!);
    final previous = doc.attachmentPath;
    if (deleteOriginal && previous != object) await _removeObject(previous);
    return object;
  }

  @override
  Future<void> remove(Document doc, {required bool deleteFile}) async {
    await _client.from('documents').delete().eq('id', doc.id!);
    if (deleteFile) await _removeObject(doc.attachmentPath);
  }

  @override
  Future<String?> attachmentUrl(String path) async {
    if (path.isEmpty) return null;
    try {
      return await _client.storage.from(_bucket).createSignedUrl(path, 3600);
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

/// Online-first with a local mirror. Reads refresh the cache; when offline the
/// cache answers. Writes require a connection (online-first, as requested).
class CachedDocumentsService implements DocumentsService {
  CachedDocumentsService(this.remote, this._db);

  final DocumentsService remote;
  final AppDatabase _db;

  @override
  Future<List<Document>> all() async {
    try {
      final docs = await remote.all();
      final db = await _db.database;
      // One transaction: a failure mid-way keeps the previous cache intact
      // instead of leaving it empty.
      await db.transaction((txn) async {
        await txn.delete('documents');
        final batch = txn.batch();
        for (final d in docs) {
          batch.insert('documents', d.toCache());
        }
        await batch.commit(noResult: true);
      });
      return docs;
    } catch (_) {
      final db = await _db.database;
      final rows = await db.query('documents', orderBy: 'datetime DESC');
      return rows.map(Document.fromMap).toList();
    }
  }

  @override
  Future<void> create(DocumentDraft draft, {String? sourceAttachmentPath}) =>
      remote.create(draft, sourceAttachmentPath: sourceAttachmentPath);

  @override
  Future<void> edit(Document doc, DocumentDraft draft, {String? newSourceAttachmentPath}) =>
      remote.edit(doc, draft, newSourceAttachmentPath: newSourceAttachmentPath);

  @override
  Future<void> remove(Document doc, {required bool deleteFile}) =>
      remote.remove(doc, deleteFile: deleteFile);

  @override
  Future<String> replaceAttachment(Document doc, String localPath, {bool deleteOriginal = true}) =>
      remote.replaceAttachment(doc, localPath, deleteOriginal: deleteOriginal);

  @override
  Future<String?> attachmentUrl(String path) => remote.attachmentUrl(path);

  @override
  Future<Uint8List?> attachmentBytes(String path) => remote.attachmentBytes(path);
}

final documentsServiceProvider = Provider<DocumentsService>(
  (ref) => CachedDocumentsService(
    SupabaseDocumentsService(Supabase.instance.client),
    ref.watch(appDatabaseProvider),
  ),
);
