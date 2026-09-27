class DocumentFilters {
  const DocumentFilters({
    this.bookNumber = '',
    this.summary = '',
    this.year = '',
    this.month = '',
    this.day = '',
    this.bookType = '',
    this.requester = '',
    this.status = '',
    this.direction = '',
  });

  final String bookNumber;
  final String summary;
  final String year;
  final String month;
  final String day;
  final String bookType;
  final String requester;
  final String status;
  final String direction;

  DocumentFilters copyWith({
    String? bookNumber,
    String? summary,
    String? year,
    String? month,
    String? day,
    String? bookType,
    String? requester,
    String? status,
    String? direction,
  }) =>
      DocumentFilters(
        bookNumber: bookNumber ?? this.bookNumber,
        summary: summary ?? this.summary,
        year: year ?? this.year,
        month: month ?? this.month,
        day: day ?? this.day,
        bookType: bookType ?? this.bookType,
        requester: requester ?? this.requester,
        status: status ?? this.status,
        direction: direction ?? this.direction,
      );
}
