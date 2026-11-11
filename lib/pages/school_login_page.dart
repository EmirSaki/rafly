import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'home_page.dart';

class SchoolLoginPage extends StatefulWidget {
  const SchoolLoginPage({super.key});

  @override
  State<SchoolLoginPage> createState() => _SchoolLoginPageState();
}

class _SchoolLoginPageState extends State<SchoolLoginPage> {
  final TextEditingController _schoolCodeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _schoolCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final schoolCode = _schoolCodeController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (schoolCode.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Okul kodu, mail ve şifre zorunlu")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final loginData = await ApiService.loginUser(
        schoolCode: schoolCode,
        email: email,
        password: password,
      );

      if (!mounted) return;

      final user = loginData["user"] ?? {};
      final school = loginData["school"] ?? {};

      final actualSchoolCode = school["school_code"]?.toString() ?? schoolCode;

      // Fetch school logo (non-blocking, fallback to null)
      String? schoolLogoUrl;
      try {
        schoolLogoUrl = await ApiService.getSchoolLogo(schoolCode: actualSchoolCode);
      } catch (_) {}

      if (!mounted) return;

      // Oturumu kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_role', 'admin');
      await prefs.setString('admin_school_code', actualSchoolCode);
      await prefs.setString('admin_school_name', school["school_name"] ?? "");
      await prefs.setString('admin_user_name', user["user_name"] ?? "");
      await prefs.setString('admin_user_surname', user["user_surname"] ?? "");
      await prefs.setString('admin_user_role', user["user_role"] ?? "");

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            schoolCode: actualSchoolCode,
            schoolName: school["school_name"] ?? "",
            userName: user["user_name"] ?? "",
            userSurname: user["user_surname"] ?? "",
            userRole: user["user_role"] ?? "",
            schoolLogoUrl: schoolLogoUrl,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Giriş başarısız: $e")),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFEDF0F8),
      body: LayoutBuilder(builder: (context, size) {
        final diameter = size.maxWidth * 1.02;
        return Stack(children: [
          Positioned(top: -diameter * .68, left: -diameter * .60, child: _SoftCircle(diameter: diameter)),
          Positioned(bottom: -diameter * .77, right: -diameter * .58, child: _SoftCircle(diameter: diameter)),
          Center(child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 32, 24,
              MediaQuery.viewInsetsOf(context).bottom + 32),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.fromLTRB(24, 46, 24, 48),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF1F3FA),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x7DFFFFFF), blurRadius: 18, offset: Offset(-12, -12)),
                  BoxShadow(color: Color(0x555F7DBE), blurRadius: 28, offset: Offset(16, 20)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.menu_book_rounded, size: 50, color: Color(0xFF092E6F)),
                const Text('Rafly', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: Color(0xFF092E6F))),
                const SizedBox(height: 2),
                const Text('Kütüphane Yönetim Sistemi', style: TextStyle(fontSize: 11, color: Color(0xFF6F7480))),
                const SizedBox(height: 20),
                _LoginField(controller: _schoolCodeController, icon: Icons.apartment_outlined, hint: 'Okul kodunu girin', keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)]),
                const SizedBox(height: 9),
                _LoginField(controller: _emailController, icon: Icons.mail_outline_rounded, hint: 'ornek@mail.com', keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 9),
                _LoginField(controller: _passwordController, icon: Icons.lock_outline_rounded, hint: 'Şifrenizi girin', obscureText: _obscurePassword,
                  suffix: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: const Color(0xFF092E6F)),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
                  onSubmitted: (_) { if (!_isLoading) _login(); }),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, height: 55, child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0862E9), foregroundColor: Colors.white,
                    shape: const StadiumBorder(), elevation: 10, shadowColor: const Color(0xFF3B7FF0),
                  ),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Expanded(child: Text('Giriş Yap', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      Icon(Icons.arrow_forward_rounded, size: 27)],
                  ),
                )),
              ]),
            ),
          )),
        ]);
      }),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  final double diameter;
  const _SoftCircle({required this.diameter});
  @override
  Widget build(BuildContext context) => Container(
    width: diameter, height: diameter,
    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF0F2F9),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x556B94E5), blurRadius: 22, offset: Offset(9, 12))]),
  );
}

class _LoginField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  const _LoginField({required this.controller, required this.icon, required this.hint, this.keyboardType,
    this.inputFormatters, this.obscureText = false, this.suffix, this.onSubmitted});
  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    decoration: BoxDecoration(color: const Color(0xFFF2F4FA), borderRadius: BorderRadius.circular(30),
      boxShadow: const [BoxShadow(color: Colors.white, blurRadius: 7, offset: Offset(-4, -4)),
        BoxShadow(color: Color(0x485D75AE), blurRadius: 8, offset: Offset(4, 5))]),
    child: TextField(controller: controller, keyboardType: keyboardType, inputFormatters: inputFormatters,
      obscureText: obscureText, autocorrect: false, textCapitalization: TextCapitalization.none,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(filled: false, hintText: hint, hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF777D89)),
        prefixIcon: Padding(padding: const EdgeInsets.all(6), child: CircleAvatar(backgroundColor: const Color(0xFFDDE6F8),
          child: Icon(icon, color: const Color(0xFF092E6F), size: 21))),
        suffixIcon: suffix, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14)),
    ),
  );
}
