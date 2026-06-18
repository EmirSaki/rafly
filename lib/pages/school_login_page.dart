import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../main.dart';
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
      backgroundColor: kBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_library_outlined,
                  size: 48,
                  color: kPrimary,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Rafly",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Kütüphane Yönetim Sistemi",
                  style: TextStyle(
                    fontSize: 14,
                    color: kTextSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Giriş Yap",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Devam etmek için bilgilerinizi girin",
                        style: TextStyle(fontSize: 13, color: kTextSecondary),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Okul Kodu",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _schoolCodeController,
                        keyboardType: TextInputType.number,
                        textCapitalization: TextCapitalization.none,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        decoration: const InputDecoration(
                          hintText: "Okul kodunu girin",
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "E-posta",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: "ornek@mail.com",
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Şifre",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        decoration: InputDecoration(
                          hintText: "Şifrenizi girin",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: kTextSecondary,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_isLoading) _login();
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text("Giriş Yap"),
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
}
