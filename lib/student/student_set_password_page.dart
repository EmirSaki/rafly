import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

/// Sunucudaki kurallarla aynı: en az 6 karakter, "1234" olamaz, tek karakter
/// tekrarı olamaz. Geçerliyse null döner.
String? validateStudentPassword(String pw) {
  if (pw.length < 6) return 'Şifre en az 6 karakter olmalı';
  if (pw.length > 72) return 'Şifre en fazla 72 karakter olabilir';
  if (pw == '1234') return 'Başlangıç şifresini kullanamazsın';
  if (RegExp(r'^(.)\1+$').hasMatch(pw)) {
    return 'Şifre tek tekrarlayan karakterlerden oluşamaz';
  }
  return null;
}

/// İlk giriş sonrası öğrencinin kendi şifresini belirlediği ekran.
/// Başarılı olursa yeni şifreyi `Navigator.pop` ile geri döndürür.
class StudentSetPasswordPage extends StatefulWidget {
  final String setupToken;
  const StudentSetPasswordPage({super.key, required this.setupToken});

  @override
  State<StudentSetPasswordPage> createState() => _StudentSetPasswordPageState();
}

class _StudentSetPasswordPageState extends State<StudentSetPasswordPage> {
  final _passCtrl = TextEditingController();
  final _repeatCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _save() async {
    final pw = _passCtrl.text;
    final error = validateStudentPassword(pw);
    if (error != null) return _showError(error);
    if (pw != _repeatCtrl.text) return _showError('Şifreler aynı değil');

    setState(() => _loading = true);
    try {
      final res = await ApiService.setStudentPassword(
        setupToken: widget.setupToken,
        newPassword: pw,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.of(context).pop(pw);
      } else {
        _showError(res['message']?.toString() ?? 'Şifre belirlenemedi');
      }
    } catch (_) {
      _showError('Bağlantı hatası');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kDestructive),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Şifre Belirle'),
        backgroundColor: kBackground,
        elevation: 0,
        foregroundColor: kTextPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kendi şifreni belirle',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: kTextPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bu hesaba ilk kez giriyorsun. Başkalarının hesabına girmemesi için '
                'yalnızca senin bildiğin bir şifre seç (en az 6 karakter).',
                style: TextStyle(fontSize: 13, color: kTextSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Yeni şifre',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _repeatCtrl,
                obscureText: _obscure,
                decoration:
                    const InputDecoration(labelText: 'Yeni şifre (tekrar)'),
                onSubmitted: (_) {
                  if (!_loading) _save();
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Şifreyi Kaydet ve Giriş Yap'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }
}
