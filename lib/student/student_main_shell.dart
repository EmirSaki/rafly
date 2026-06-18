import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_auth_provider.dart';
import '../main.dart';
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
      const StudentHomeScreen(),
      StudentBooksScreen(schoolCode: schoolCode),
      const StudentReservationsScreen(),
      const StudentProfileScreen(),
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
          color: kSurface,
          border: const Border(top: BorderSide(color: kBorder, width: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(4, (i) => _tabItem(i, labels[i], icons[i])),
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
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: active ? kPrimary : kTextSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? kPrimary : kTextSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
