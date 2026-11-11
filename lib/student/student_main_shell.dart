import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_auth_provider.dart';
import 'student_home_screen.dart';
import 'student_books_screen.dart';
import 'student_reservations_screen.dart';
import 'student_profile_screen.dart';

class StudentMainShell extends StatefulWidget {
  const StudentMainShell({super.key});
  @override
  State<StudentMainShell> createState() => _StudentMainShellState();
}

class _StudentMainShellState extends State<StudentMainShell> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<StudentAuthProvider>();
    final schoolCode = auth.schoolCode ?? '';

    final screens = [
      StudentHomeScreen(
        onOpenHistory: () => setState(() => _idx = 2),
        onOpenBooks: () => setState(() => _idx = 1),
      ),
      StudentBooksScreen(
        schoolCode: schoolCode,
        onBack: () => setState(() => _idx = 0),
      ),
      StudentReservationsScreen(onBack: () => setState(() => _idx = 0)),
      StudentProfileScreen(onBack: () => setState(() => _idx = 0)),
    ];

    const labels = ['Anasayfa', 'Kitaplar', 'Geçmiş', 'Profil'];
    const icons = [
      Icons.home_rounded,
      Icons.library_books_rounded,
      Icons.history_rounded,
      Icons.person_rounded,
    ];

    return Scaffold(
      body: IndexedStack(index: _idx, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8AA7D8).withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 76,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                4,
                (i) => _tabItem(i, labels[i], icons[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabItem(int i, String label, IconData icon) {
    final active = _idx == i;
    return GestureDetector(
      onTap: () => setState(() => _idx = i),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 40,
              decoration: BoxDecoration(
                color: active ? const Color(0xFFE7EEFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                size: 26,
                color: active
                    ? const Color(0xFF0765EA)
                    : const Color(0xFF5A74A4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active
                    ? const Color(0xFF0765EA)
                    : const Color(0xFF5A74A4),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
