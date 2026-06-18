import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/student_auth_provider.dart';
import '../main.dart';

class StudentLoginPage extends StatefulWidget {
  const StudentLoginPage({super.key});
  @override
  State<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends State<StudentLoginPage> {
  final _schoolCodeCtrl = TextEditingController();
  final _studentNumberCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _schoolLevel = 'ortaokul';
  bool _loading = false;
  bool _obscure = true;

  final _levels = const ['ilkokul', 'ortaokul', 'lise', 'hazırlık', 'diğer'];
  final _levelLabels = const {
    'ilkokul': 'İlkokul',
    'ortaokul': 'Ortaokul',
    'lise': 'Lise',
    'hazırlık': 'Hazırlık',
    'diğer': 'Diğer',
  };

  Future<void> _handleLogin() async {
    final schoolCode = _schoolCodeCtrl.text.trim();
    final studentNumber = _studentNumberCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (schoolCode.isEmpty || studentNumber.isEmpty || password.isEmpty) {
      _showError('Tüm alanları doldurun');
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<StudentAuthProvider>().login(
            schoolCode: schoolCode,
            schoolLevel: _schoolLevel,
            studentNumber: studentNumber,
            password: password,
          );
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.school_outlined, size: 48, color: kPrimary),
                const SizedBox(height: 12),
                const Text(
                  'Rafly',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: kPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Öğrenci Paneli',
                  style: TextStyle(fontSize: 14, color: kTextSecondary),
                ),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Giriş Yap',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: kTextPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Devam etmek için bilgilerinizi girin',
                        style: TextStyle(fontSize: 13, color: kTextSecondary),
                      ),
                      const SizedBox(height: 20),

                      _fieldLabel('Okul Kodu'),
                      TextField(
                        controller: _schoolCodeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        decoration: const InputDecoration(hintText: 'Okul kodunu girin'),
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('Okul Seviyesi'),
                      _levelSelector(),
                      const SizedBox(height: 14),

                      _fieldLabel('Öğrenci Numarası'),
                      TextField(
                        controller: _studentNumberCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(hintText: '1234'),
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('Şifre'),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          hintText: 'Şifrenizi girin',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: kTextSecondary,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_loading) _handleLogin();
                        },
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _handleLogin,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Giriş Yap'),
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

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary),
        ),
      );

  Widget _levelSelector() => Container(
        decoration: BoxDecoration(
          color: kMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: _levels.map((level) {
            final selected = _schoolLevel == level;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _schoolLevel = level),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? kPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    _levelLabels[level] ?? level,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : kTextSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );

  @override
  void dispose() {
    _schoolCodeCtrl.dispose();
    _studentNumberCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}
