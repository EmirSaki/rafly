import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rafly/services/staff_session.dart';

void main() {
  const api = 'https://api.example.test';
  late Map<String, String> seen;
  late StaffAuthClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StaffSession.clear();
    seen = {};
    client = StaffAuthClient(
      api,
      MockClient((request) async {
        seen = request.headers;
        return http.Response('{}', 200);
      }),
    );
  });

  test('personel token\'ı varsa API isteğine eklenir', () async {
    await StaffSession.save('abc123');
    await client.get(Uri.parse('$api/api/students?schoolCode=1'));
    expect(seen['Authorization'], 'Bearer abc123');
  });

  test('token yoksa başlık eklenmez', () async {
    await client.get(Uri.parse('$api/api/students?schoolCode=1'));
    expect(seen.containsKey('Authorization'), isFalse);
  });

  test('öğrenci isteğinin kendi Authorization başlığı ezilmez', () async {
    await StaffSession.save('abc123');
    await client.get(
      Uri.parse('$api/api/students/profile'),
      headers: {'Authorization': 'Bearer ogrenci-token'},
    );
    expect(seen['Authorization'], 'Bearer ogrenci-token');
  });

  test('token başka sunuculara gönderilmez', () async {
    await StaffSession.save('abc123');
    await client.get(Uri.parse('https://baska-site.test/kapak.jpg'));
    expect(seen.containsKey('Authorization'), isFalse);
  });

  test('çıkışta token silinir ve kalıcı depodan da kalkar', () async {
    await StaffSession.save('abc123');
    await StaffSession.clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('admin_token'), isNull);
    await client.get(Uri.parse('$api/api/students?schoolCode=1'));
    expect(seen.containsKey('Authorization'), isFalse);
  });
}
