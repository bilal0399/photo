class Task {
  const Task({
    this.id,
    required this.taskNumber,
    required this.entity,
    required this.attachmentPath,
    required this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String taskNumber;
  final String entity;
  final String attachmentPath;
  final String createdAt;
  final String? updatedAt;

  bool get hasAttachment => attachmentPath.isNotEmpty;

  Task copyWith({
    String? id,
    String? taskNumber,
    String? entity,
    String? attachmentPath,
    String? updatedAt,
  }) =>
      Task(
        id: id ?? this.id,
        taskNumber: taskNumber ?? this.taskNumber,
        entity: entity ?? this.entity,
        attachmentPath: attachmentPath ?? this.attachmentPath,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory Task.fromMap(Map<String, Object?> map) => Task(
        id: map['id'] as String?,
        taskNumber: (map['task_number'] as String?) ?? '',
        entity: (map['entity'] as String?) ?? '',
        attachmentPath: (map['attachment_path'] as String?) ?? '',
        createdAt: (map['created_at'] as String?) ?? '',
        updatedAt: map['updated_at'] as String?,
      );

  /// Row shape used by the local (offline) cache.
  Map<String, Object?> toCache() => {
        'id': id,
        'task_number': taskNumber,
        'entity': entity,
        'attachment_path': attachmentPath,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// A folder in the tasks view: one entity plus how many tasks it holds.
class TaskFolder {
  const TaskFolder({required this.entity, required this.count});

  final String entity;
  final int count;
}
