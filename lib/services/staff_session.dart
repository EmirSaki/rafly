import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Personel (öğretmen/yönetici) oturumunun JWT'si.
///
/// `/api/users/login` yanıtındaki token cihazda saklanır ve API'ye giden her
/// isteğe `Authorization: Bearer ...` olarak eklenir. Sunucu yetki kontrolünü
/// zorunlu tuttuğunda (AUTH_MODE=enforce) uygulama hazırdır.
class StaffSession {
  static const String _prefKey = 'admin_token';
  static const String _studentPrefKey = 'student_token';
  static const List<String> _adminPrefKeys = [
    'app_role',
    'admin_school_code',
    'admin_school_name',
    'admin_user_name',
    'admin_user_surname',
    'admin_user_role',
  ];

  static String? _token;
  static bool _loaded = false;
  static bool _handlingUnauthorized = false;

  /// Personel oturumu sunucuda geçersiz olduğunda (401) çağrılır; uygulama
  /// kullanıcıyı giriş ekranına götürür. `main()` içinde atanır.
  static Future<void> Function()? onSessionExpired;

  static Future<String?> token() async {
    if (!_loaded) {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_prefKey);
      _loaded = true;
    }
    return _token;
  }

  static Future<void> save(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    _loaded = true;
    if (value == null || value.trim().isEmpty) {
      _token = null;
      await prefs.remove(_prefKey);
    } else {
      _token = value.trim();
      await prefs.setString(_prefKey, _token!);
    }
  }

  static Future<void> clear() => save(null);

  /// Öğrenci oturumunun token'ı (öğrenci girişinde kaydedilir).
  static Future<String?> studentToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_studentPrefKey);
  }

  /// Sunucu 401 döndü: cihazdaki personel oturumu varsa kapatılır ve giriş
  /// ekranına dönülür. Öğrenci oturumuna dokunmaz. Oturum kapatıldıysa true.
  static Future<bool> handleUnauthorized() async {
    if (_handlingUnauthorized) return false;
    _handlingUnauthorized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('app_role') != 'admin') return false;
      for (final key in _adminPrefKeys) {
        await prefs.remove(key);
      }
      await clear();
      await onSessionExpired?.call();
      return true;
    } finally {
      _handlingUnauthorized = false;
    }
  }
}

/// API isteklerine oturum token'ını ekleyen HTTP istemcisi.
///
/// - İstek kendi `Authorization` başlığını taşıyorsa dokunmaz.
/// - Personel oturumu varsa personel token'ını, yoksa öğrenci token'ını ekler
///   (öğrencinin kitap listesi/duyuru istekleri için).
/// - Token yalnızca API sunucusuna gönderilir.
/// - Sunucu 401 dönerse personel oturumunu kapatır.
class StaffAuthClient extends http.BaseClient {
  StaffAuthClient(this.apiBaseUrl, [http.Client? inner]) : _inner = inner ?? http.Client();

  final String apiBaseUrl;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final hasOwnAuth = request.headers.keys.any((k) => k.toLowerCase() == 'authorization');
    final isApi = request.url.toString().startsWith(apiBaseUrl);

    if (!hasOwnAuth && isApi) {
      final token = await StaffSession.token() ?? await StaffSession.studentToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await _inner.send(request);

    final isLogin = request.url.path.endsWith('/login');
    if (response.statusCode == 401 && isApi && !hasOwnAuth && !isLogin) {
      await StaffSession.handleUnauthorized();
    }
    return response;
  }
}
