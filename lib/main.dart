import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/student_auth_provider.dart';
import 'pages/school_login_page.dart';
import 'pages/home_page.dart';
import 'services/notification_service.dart';
import 'student/student_login_page.dart';
import 'student/student_main_shell.dart';
import 'student/student_profile_setup_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const Color kPrimary = Color(0xFF1A3366);
const Color kPrimaryLight = Color(0xFF2A4A80);
const Color kBorder = Color(0xFFE5E7EB);
const Color kBackground = Color(0xFFF9FAFB);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF111827);
const Color kTextSecondary = Color(0xFF6B7280);
const Color kMuted = Color(0xFFF3F4F6);
const Color kDestructive = Color(0xFFDC2626);
const Color kSuccess = Color(0xFF16A34A);
const Color kWarning = Color(0xFFF59E0B);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await NotificationService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => StudentAuthProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          primary: kPrimary,
          onPrimary: Colors.white,
          surface: kSurface,
          onSurface: kTextPrimary,
          error: kDestructive,
        ),
        scaffoldBackgroundColor: kBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: kTextPrimary,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
        cardTheme: CardThemeData(
          color: kSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: kBorder),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kPrimary, width: 1.5),
          ),
          labelStyle: const TextStyle(color: kTextSecondary, fontSize: 14),
          hintStyle: const TextStyle(color: kTextSecondary, fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kTextPrimary,
            side: const BorderSide(color: kBorder),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kTextSecondary,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: kBorder,
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(fontSize: 14, color: kTextPrimary),
        ),
      ),
      home: const AppGate(),
    );
  }
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});
  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _checking = true;
  String? _savedRole; // 'admin' veya 'student'
  Map<String, String>? _adminData;

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('app_role');

    if (role == 'admin') {
      final schoolCode = prefs.getString('admin_school_code');
      final schoolName = prefs.getString('admin_school_name') ?? '';
      final userName = prefs.getString('admin_user_name') ?? '';
      final userSurname = prefs.getString('admin_user_surname') ?? '';
      final userRole = prefs.getString('admin_user_role') ?? '';

      if (schoolCode != null && schoolCode.isNotEmpty) {
        _savedRole = 'admin';
        _adminData = {
          'schoolCode': schoolCode,
          'schoolName': schoolName,
          'userName': userName,
          'userSurname': userSurname,
          'userRole': userRole,
        };
      }
    } else if (role == 'student') {
      _savedRole = 'student';
    }

    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: kBackground,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    if (_savedRole == 'admin' && _adminData != null) {
      return HomePage(
        schoolCode: _adminData!['schoolCode']!,
        schoolName: _adminData!['schoolName']!,
        userName: _adminData!['userName']!,
        userSurname: _adminData!['userSurname']!,
        userRole: _adminData!['userRole']!,
      );
    }

    if (_savedRole == 'student') {
      return const StudentAuthGate();
    }

    return const RoleSelectionPage();
  }
}

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

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
                const Icon(Icons.local_library_outlined, size: 56, color: kPrimary),
                const SizedBox(height: 14),
                const Text(
                  'Rafly',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: kPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kütüphane Yönetim Sistemi',
                  style: TextStyle(fontSize: 14, color: kTextSecondary),
                ),
                const SizedBox(height: 48),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Giriş türünüzü seçin',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimary),
                  ),
                ),
                const SizedBox(height: 16),

                _RoleCard(
                  icon: Icons.person_outlined,
                  title: 'Yetkili Girişi',
                  subtitle: 'Kitap ekleme, ödünç verme, öğrenci yönetimi',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SchoolLoginPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.school_outlined,
                  title: 'Öğrenci/Öğretmen Girişi',
                  subtitle: 'Kitap listesi, rezervasyonlar, profil',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StudentAuthGate()),
                    );
                  },
                ),

                const SizedBox(height: 48),
                const Text(
                  'Rafly v1.0.0',
                  style: TextStyle(fontSize: 11, color: kTextSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kPrimary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kTextPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: kTextSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentAuthGate extends StatelessWidget {
  const StudentAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<StudentAuthProvider>();

    if (auth.loading) {
      return const Scaffold(
        backgroundColor: kBackground,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    if (!auth.isLoggedIn) return const StudentLoginPage();
    if (!auth.profileCompleted) return const StudentProfileSetupScreen();
    return const StudentMainShell();
  }
}
