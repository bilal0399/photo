class OptionItem {
  const OptionItem({
    this.id,
    required this.category,
    required this.value,
    required this.createdAt,
  });

  final int? id;
  final String category;
  final String value;
  final String createdAt;

  factory OptionItem.fromMap(Map<String, Object?> map) => OptionItem(
        id: map['id'] as int?,
        category: map['category'] as String,
        value: map['value'] as String,
        createdAt: map['created_at'] as String,
      );
}
