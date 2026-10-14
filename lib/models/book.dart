class Book {
  final int? bookId;
  final String title;
  final List<String> authors;
  final String publisher;
  final List<String> categories;
  final String isbn;
  final int? quantity;
  final int? availableQuantity;
  final int pageCount;
  final int volumeCount;
  final String? shelf;
  final String? coverUrl;
  final bool isValilikBook;

  Book({
    this.bookId,
    required this.title,
    required this.authors,
    required this.publisher,
    required this.categories,
    required this.isbn,
    this.quantity,
    this.availableQuantity,
    this.pageCount = 0,
    this.volumeCount = 0,
    this.shelf,
    this.coverUrl,
    this.isValilikBook = false,
  });

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == 't' || v == '1';
    }
    return false;
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [];
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      bookId: json['book_id'],
      title: (json['title'] ?? json['book_name'] ?? '').toString(),
      authors: _toStringList(
        json['authors'] ??
            (json['book_writer'] != null ? json['book_writer'].toString() : null),
      ),
      publisher: (json['publisher'] ?? '').toString(),
      categories: _toStringList(
        json['categories'] ??
            (json['book_genre'] != null ? json['book_genre'].toString() : null),
      ),
      isbn: (json['isbn'] ?? '').toString(),
      quantity: json['quantity'] ?? json['book_quantity'],
      availableQuantity: int.tryParse(
        '${json['available_quantity'] ?? json['availableQuantity'] ?? 0}',
      ) ?? 0,
      pageCount: int.tryParse('${json['pageCount'] ?? json['page_count'] ?? 0}') ?? 0,
      volumeCount: int.tryParse('${json['volumeCount'] ?? json['volume_count'] ?? 0}') ?? 0,
      shelf: (json['shelf'] == null || json['shelf'].toString().trim().isEmpty)
          ? null
          : json['shelf'].toString().trim(),
      coverUrl: (() {
        final raw = (json['cover_url'] ?? json['coverUrl'] ?? '').toString().trim();
        return raw.isEmpty ? null : raw;
      })(),
      isValilikBook: _toBool(json['is_valilik_book'] ?? json['isValilikBook']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'book_id': bookId,
      'title': title,
      'authors': authors,
      'publisher': publisher,
      'categories': categories,
      'isbn': isbn,
      'quantity': quantity,
      'available_quantity': availableQuantity,
      'pageCount': pageCount,
      'volumeCount': volumeCount,
      'shelf': shelf,
      'cover_url': coverUrl,
      'is_valilik_book': isValilikBook,
    };
  }
}