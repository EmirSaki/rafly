import 'dart:async';
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

  test('personel oturumu yoksa öğrenci tokenı eklenir', () async {
    SharedPreferences.setMockInitialValues({'student_token': 'ogr-1'});
    await client.get(Uri.parse('$api/api/schools/1/books'));
    expect(seen['Authorization'], 'Bearer ogr-1');
  });

  test('401 gelirse personel oturumu kapatılır ve giriş ekranı istenir', () async {
    SharedPreferences.setMockInitialValues({'app_role': 'admin', 'admin_school_code': '1'});
    await StaffSession.save('eski-token');
    var expired = 0;
    StaffSession.onSessionExpired = () async => expired++;
    final rejecting = StaffAuthClient(api, MockClient((_) async => http.Response('{}', 401)));
    await rejecting.get(Uri.parse('$api/api/students?schoolCode=1'));
    final prefs = await SharedPreferences.getInstance();
    expect(expired, 1);
    expect(prefs.getString('app_role'), isNull);
    expect(prefs.getString('admin_token'), isNull);
    StaffSession.onSessionExpired = null;
  });

  test('401 öğrenci oturumunu kapatmaz; hatalı giriş denemesi de oturum kapatmaz', () async {
    SharedPreferences.setMockInitialValues({'app_role': 'student', 'student_token': 'ogr-1'});
    var expired = 0;
    StaffSession.onSessionExpired = () async => expired++;
    final rejecting = StaffAuthClient(api, MockClient((_) async => http.Response('{}', 401)));
    await rejecting.get(Uri.parse('$api/api/schools/1/books'));
    await rejecting.post(Uri.parse('$api/api/users/login'));
    final prefs = await SharedPreferences.getInstance();
    expect(expired, 0);
    expect(prefs.getString('student_token'), 'ogr-1');
    StaffSession.onSessionExpired = null;
  });

  test('çıkışta token silinir ve kalıcı depodan da kalkar', () async {
    await StaffSession.save('abc123');
    await StaffSession.clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('admin_token'), isNull);
    await client.get(Uri.parse('$api/api/students?schoolCode=1'));
    expect(seen.containsKey('Authorization'), isFalse);
  });

  test('sunucu yanıt vermezse zaman aşımı fırlatır (ekran sonsuza dek beklemez)', () async {
    final slow = StaffAuthClient(
      api,
      MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{}', 200);
      }),
      const Duration(milliseconds: 50),
    );
    expect(
      () => slow.get(Uri.parse('$api/api/books')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('zaman aşımı sınırı altında gelen yanıt normal döner', () async {
    final ok = StaffAuthClient(
      api,
      MockClient((request) async => http.Response('{"success":true}', 200)),
      const Duration(milliseconds: 500),
    );
    final res = await ok.get(Uri.parse('$api/api/books'));
    expect(res.statusCode, 200);
  });
}
