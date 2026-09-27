import 'package:path/path.dart' as p;

const kApprovedStatus = 'تمت الموافقة';

const kOutgoing = 'صادر';
const kIncoming = 'وارد';
const kDirections = [kOutgoing, kIncoming];

/// Recipients offered for outgoing books until the `recipient` option list is
/// filled in on the server; the server list wins whenever it has values.
const kDefaultRecipients = ['الوزارة', 'قيادة الفيلق'];

/// An incoming book comes *from* a party, an outgoing one goes *to* one — the
/// same field, labelled by direction.
String entityLabel(String direction) =>
    direction == kOutgoing ? 'الجهة المستقبلة' : 'الجهة المقدمة';

const _imageExt = {'.png', '.jpg', '.jpeg'};

class Document {
  const Document({
    this.id,
    required this.documentCode,
    required this.bookNumber,
    required this.datetime,
    required this.bookType,
    required this.requester,
    required this.status,
    required this.direction,
    required this.summary,
    required this.attachmentPath,
    required this.approvalDate,
    required this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String documentCode;
  final String bookNumber;
  final String datetime;
  final String bookType;
  final String requester;
  final String status;
  final String direction;
  final String summary;
  final String attachmentPath;
  final String approvalDate;
  final String createdAt;
  final String? updatedAt;

  bool get hasAttachment => attachmentPath.isNotEmpty;
  bool get isImageAttachment =>
      hasAttachment && _imageExt.contains(p.extension(attachmentPath).toLowerCase());
  String get dateOnly => datetime.isEmpty ? '' : datetime.split(' ').first;

  /// Row shape used by the local (offline) cache — keys match the sqflite table.
  Map<String, Object?> toCache() => {
        'id': id,
        'document_code': documentCode,
        'book_number': bookNumber,
        'datetime': datetime,
        'book_type': bookType,
        'requester': requester,
        'status': status,
        'direction': direction,
        'summary': summary,
        'attachment_path': attachmentPath,
        'approval_date': approvalDate,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Document.fromMap(Map<String, Object?> m) => Document(
        id: m['id'] as String?,
        documentCode: (m['document_code'] as String?) ?? '',
        bookNumber: (m['book_number'] as String?) ?? '',
        datetime: m['datetime'] as String? ?? '',
        bookType: m['book_type'] as String? ?? '',
        requester: m['requester'] as String? ?? '',
        status: m['status'] as String? ?? '',
        direction: m['direction'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        attachmentPath: (m['attachment_path'] as String?) ?? '',
        approvalDate: (m['approval_date'] as String?) ?? '',
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String?,
      );
}

/// Editable fields captured by the document form.
class DocumentDraft {
  const DocumentDraft({
    required this.bookNumber,
    required this.datetime,
    required this.bookType,
    required this.requester,
    required this.status,
    required this.direction,
    required this.summary,
  });

  final String bookNumber;
  final String datetime;
  final String bookType;
  final String requester;
  final String status;
  final String direction;
  final String summary;
}
