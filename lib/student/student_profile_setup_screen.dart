import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_auth_provider.dart';
import '../services/api_service.dart';
import '../main.dart';

class StudentProfileSetupScreen extends StatefulWidget {
  const StudentProfileSetupScreen({super.key});
  @override
  State<StudentProfileSetupScreen> createState() => _StudentProfileSetupScreenState();
}

class _StudentProfileSetupScreenState extends State<StudentProfileSetupScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (email.isEmpty || phone.isEmpty) {
      _showError('Email ve telefon numarası zorunludur.');
      return;
    }
    if (!email.contains('@')) {
      _showError('Geçerli bir email girin.');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await ApiService.updateStudentProfile(email: email, phone: phone);
      if (res['success'] == true && mounted) {
        context.read<StudentAuthProvider>().markProfileCompleted(res['data'] ?? {});
      } else {
        _showError(res['message'] ?? 'Hata oluştu');
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
    final auth = context.watch<StudentAuthProvider>();
    final name = '${auth.user?['user_name'] ?? ''} ${auth.user?['user_surname'] ?? ''}'.trim();

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Icon(Icons.person_add_rounded, size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Profilini Tamamla',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kTextPrimary)),
                const SizedBox(height: 8),
                Text('Hoşgeldin $name! Devam etmek için bilgilerini tamamla.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                    boxShadow: const [
                      BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _fieldLabel('E-posta'),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(hintText: 'ornek@email.com'),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Telefon Numarası'),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: '05XX XXX XX XX'),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _save,
                          child: _loading
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Kaydet ve Devam Et'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () async {
                                  await context.read<StudentAuthProvider>().logout();
                                },
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Farklı Hesapla Giriş Yap'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kTextSecondary,
                            side: const BorderSide(color: kBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
        ),
      );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }
}
