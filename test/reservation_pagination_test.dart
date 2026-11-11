import 'package:flutter_test/flutter_test.dart';
import 'package:rafly/pages/reservation_pagination.dart';

void main() {
  test('each column shows at most ten records on the same page', () {
    final loaned = List.generate(23, (index) => 'loan $index');
    final returned = List.generate(11, (index) => 'return $index');

    expect(reservationPageCount(loaned.length, returned.length), 3);
    expect(reservationPage(loaned, 0), loaned.take(10).toList());
    expect(reservationPage(returned, 0), returned.take(10).toList());
    expect(reservationPage(loaned, 1), loaned.skip(10).take(10).toList());
    expect(reservationPage(returned, 1), ['return 10']);
    expect(reservationPage(loaned, 2), loaned.skip(20).toList());
    expect(reservationPage(returned, 2), isEmpty);
  });

  test('empty and single page stay on page one', () {
    expect(reservationPageCount(0, 0), 1);
    expect(reservationPageCount(2, 8), 1);
  });
}
