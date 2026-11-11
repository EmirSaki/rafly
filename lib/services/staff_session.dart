import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Personel (öğretmen/yönetici) oturumunun JWT'si.
///
/// `/api/users/login` yanıtındaki token cihazda saklanır ve API'ye giden her
/// isteğe `Authorization: Bearer ...` olarak eklenir. Sunucu şu an çoğu uçta
/// bunu zorunlu tutmuyor; zorunlu hale geldiğinde uygulama hazır olur.
class StaffSession {
  static const String _prefKey = 'admin_token';
  static String? _token;
  static bool _loaded = false;

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
}

/// API isteklerine personel token'ını ekleyen HTTP istemcisi.
/// İstek kendi `Authorization` başlığını taşıyorsa (öğrenci oturumu) ya da
/// hedef API sunucusu değilse dokunmaz.
class StaffAuthClient extends http.BaseClient {
  StaffAuthClient(this.apiBaseUrl, [http.Client? inner]) : _inner = inner ?? http.Client();

  final String apiBaseUrl;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final hasAuth = request.headers.keys.any((k) => k.toLowerCase() == 'authorization');
    if (!hasAuth && request.url.toString().startsWith(apiBaseUrl)) {
      final token = await StaffSession.token();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }
    return _inner.send(request);
  }
}
