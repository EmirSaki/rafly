import 'package:flutter_test/flutter_test.dart';
import 'package:rafly/student/student_set_password_page.dart';

void main() {
  test('şifre kuralları sunucuyla aynı', () {
    final v = validateStudentPassword;
    expect(v('12345'), isNotNull); // çok kısa
    expect(v('1234'), isNotNull); // başlangıç şifresi
    expect(v('111111'), isNotNull); // tek karakter tekrarı
    expect(v('a' * 73), isNotNull); // çok uzun
    expect(v('kitap-2026'), isNull);
    expect(v('123456'), isNull);
  });
}
