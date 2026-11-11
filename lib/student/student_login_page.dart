import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/student_auth_provider.dart';
import '../main.dart';
import 'student_set_password_page.dart';

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

  final _levels = const ['ilkokul', 'ortaokul', 'lise', 'diğer'];
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
    } on PasswordSetupRequired catch (setup) {
      if (!mounted) return;
      final newPassword = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => StudentSetPasswordPage(setupToken: setup.setupToken),
        ),
      );
      if (newPassword != null && mounted) {
        // Şifre belirlendi: yeni şifreyle otomatik giriş yap
        try {
          await context.read<StudentAuthProvider>().login(
                schoolCode: schoolCode,
                schoolLevel: _schoolLevel,
                studentNumber: studentNumber,
                password: newPassword,
              );
        } catch (e) {
          _showError(e.toString().replaceAll('Exception: ', ''));
        }
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kDestructive));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFEDF0F8),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final diameter = width * 1.06;
          return Stack(
            children: [
              Positioned(
                top: -diameter * .70,
                left: -diameter * .63,
                child: _LoginCircle(diameter: diameter),
              ),
              Positioned(
                bottom: -diameter * .82,
                right: -diameter * .62,
                child: _LoginCircle(diameter: diameter),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 24, 16,
                      MediaQuery.viewInsetsOf(context).bottom + 24),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 510),
                      padding: const EdgeInsets.fromLTRB(32, 42, 32, 48),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF1F3FA),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xAAFFFFFF),
                            blurRadius: 22,
                            offset: Offset(-12, -12),
                          ),
                          BoxShadow(
                            color: Color(0x77608BE6),
                            blurRadius: 30,
                            offset: Offset(16, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.school_outlined,
                                  size: 37,
                                  color: Color(0xFF092E6F),
                                ),
                                Text(
                                  'Rafly',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF092E6F),
                                  ),
                                ),
                                Text(
                                  'Öğrenci Paneli',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7D8495),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Giriş Yap',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF092E6F),
                            ),
                          ),
                          const Text(
                            'Devam etmek için bilgilerinizi girin.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7D8495),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _fieldLabel('Okul Kodu'),
                          _input(
                            _schoolCodeCtrl,
                            Icons.apartment_outlined,
                            'Okul kodunu girin',
                            keyboard: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(12),
                            ],
                          ),
                          const SizedBox(height: 11),
                          _fieldLabel('Okul Seviyesi'),
                          _levelSelector(),
                          const SizedBox(height: 11),
                          _fieldLabel('Öğrenci Numarası'),
                          _input(
                            _studentNumberCtrl,
                            Icons.tag,
                            '1234',
                            keyboard: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                          const SizedBox(height: 11),
                          _fieldLabel('Şifre'),
                          _input(
                            _passwordCtrl,
                            Icons.lock_outline_rounded,
                            'Şifrenizi girin',
                            obscure: _obscure,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFF092E6F),
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            onSubmitted: (_) {
                              if (!_loading) _handleLogin();
                            },
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'İlk girişte şifre: 1234. Ardından kendi şifreni belirlersin.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF929AB0),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 53,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0862E9),
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                elevation: 11,
                                shadowColor: const Color(0xFF3B7FF0),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Giriş Yap',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        CircleAvatar(
                                          backgroundColor: Color(0xFF2879F0),
                                          child: Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    IconData icon,
    String hint, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(32),
      boxShadow: const [
        BoxShadow(
          color: Color(0x556E8DC9),
          blurRadius: 13,
          offset: Offset(3, 8),
        ),
        BoxShadow(color: Colors.white, blurRadius: 8, offset: Offset(-5, -5)),
      ],
    ),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF156BE2)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF8FAFF),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(32),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: kTextPrimary,
      ),
    ),
  );

  Widget _levelSelector() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(32),
      boxShadow: const [
        BoxShadow(
          color: Color(0x557A98CE),
          blurRadius: 11,
          offset: Offset(3, 7),
        ),
      ],
    ),
    child: Row(
      children: _levels.map((level) {
        final selected =
            _schoolLevel == level ||
            (level == 'diğer' && _schoolLevel == 'hazırlık');
        return Expanded(
          child: GestureDetector(
            onTap: () async {
              if (level != 'diğer') {
                setState(() => _schoolLevel = level);
                return;
              }
              final choice = await showModalBottomSheet<String>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('Diğer'),
                        onTap: () => Navigator.pop(context, 'diğer'),
                      ),
                      ListTile(
                        title: const Text('Hazırlık'),
                        onTap: () => Navigator.pop(context, 'hazırlık'),
                      ),
                    ],
                  ),
                ),
              );
              if (choice != null && mounted) {
                setState(() => _schoolLevel = choice);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF0862E9) : Colors.transparent,
                borderRadius: BorderRadius.circular(32),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x88447EEC),
                          blurRadius: 10,
                          offset: Offset(2, 5),
                        ),
                      ]
                    : null,
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

class _LoginCircle extends StatelessWidget {
  final double diameter;
  const _LoginCircle({required this.diameter});

  @override
  Widget build(BuildContext context) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFF0F2F9),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x556B94E5),
          blurRadius: 22,
          offset: Offset(9, 12),
        ),
      ],
    ),
  );
}
