import 'package:flutter_test/flutter_test.dart';
import 'package:rafly/models/book.dart';

void main() {
  test('book keeps every shelf location returned by the API', () {
    final book = Book.fromJson({
      'title': 'Örnek',
      'shelf': 'A-1',
      'shelves': ['A-1', 'B-2'],
    });
    expect(book.shelves, ['A-1', 'B-2']);
  });

  test('older single shelf response remains visible', () {
    final book = Book.fromJson({'title': 'Örnek', 'shelf': 'C-3'});
    expect(book.shelves, ['C-3']);
  });
}
