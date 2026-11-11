import 'package:flutter_test/flutter_test.dart';
import 'package:rafly/pages/class_order.dart';

void main() {
  test('classes follow grade then alphabetical section', () {
    final classes = ['8B', '6C', '5D', '7A', '5B', '6A', '5A', '8A', '5C'];
    classes.sort(compareClassNames);
    expect(classes, ['5A', '5B', '5C', '5D', '6A', '6C', '7A', '8A', '8B']);
  });
}
