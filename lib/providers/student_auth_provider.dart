import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class StudentAuthProvider extends ChangeNotifier {
  bool _loading = true;
  bool _loggedIn = false;
  bool _profileCompleted = false;
  Map<String, dynamic>? _user;
  String? _token;
  String? _schoolCode;
  String? _schoolLevel;

  bool get loading => _loading;
  bool get isLoggedIn => _loggedIn;
  bool get profileCompleted => _profileCompleted;
  Map<String, dynamic>? get user => _user;
  String? get token => _token;
  String? get schoolCode => _schoolCode;
  String? get schoolLevel => _schoolLevel;

  StudentAuthProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('student_token');
    _schoolCode = prefs.getString('student_school_code');
    _schoolLevel = prefs.getString('student_school_level');

    if (_token != null) {
      try {
        final res = await ApiService.getStudentProfile();
        if (res['success'] == true) {
          _user = res['data'];
          _loggedIn = true;
          _profileCompleted = _user?['profile_completed'] == true;
        } else {
          await _clearSession();
        }
      } catch (_) {
        await _clearSession();
      }
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> login({
    required String schoolCode,
    required String schoolLevel,
    required String studentNumber,
    required String password,
  }) async {
    final res = await ApiService.studentLogin(
      schoolCode: schoolCode,
      studentNumber: studentNumber,
      password: password,
      schoolLevel: schoolLevel,
    );

    if (res['success'] != true) {
      throw Exception(res['message'] ?? 'Giriş yapılamadı');
    }

    _token = res['token'];
    _user = res['data'];
    _schoolCode = schoolCode;
    _schoolLevel = schoolLevel;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_role', 'student');
    await prefs.setString('student_token', _token!);
    await prefs.setString('student_school_code', schoolCode);
    await prefs.setString('student_school_level', schoolLevel);

    try {
      final profileRes = await ApiService.getStudentProfile();
      if (profileRes['success'] == true) {
        _profileCompleted = profileRes['data']?['profile_completed'] == true;
        _user = {...?_user, ...profileRes['data']};
      }
    } catch (_) {
      _profileCompleted = false;
    }

    _loggedIn = true;
    notifyListeners();
  }

  void markProfileCompleted(Map<String, dynamic> updatedUser) {
    _user = {...?_user, ...updatedUser};
    _profileCompleted = true;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      final res = await ApiService.getStudentProfile();
      if (res['success'] == true) {
        _user = {...?_user, ...res['data']};
        _profileCompleted = res['data']?['profile_completed'] == true;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _token = null;
    _user = null;
    _loggedIn = false;
    _profileCompleted = false;
    _schoolCode = null;
    _schoolLevel = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_role');
    await prefs.remove('student_token');
    await prefs.remove('student_school_code');
    await prefs.remove('student_school_level');
  }
}
