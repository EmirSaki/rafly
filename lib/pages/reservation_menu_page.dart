import 'package:flutter/material.dart';
import 'loan_book_page.dart';
import 'return_book_page.dart';
import 'reservation_list_page.dart';

class ReservationMenuPage extends StatelessWidget {
  final String schoolCode;

  const ReservationMenuPage({
    super.key,
    required this.schoolCode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF7FF),
      body: SafeArea(
        child: Stack(children: [
          Positioned(bottom: -126, left: -100, child: Container(width: 540, height: 230,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFB8DBFB)))),
          Positioned(bottom: -155, left: -105, child: Container(width: 550, height: 230,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF67ADEF)))),
          Positioned(bottom: -185, left: -120, child: Container(width: 560, height: 230,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF287BCE)))),
          SingleChildScrollView(padding: const EdgeInsets.fromLTRB(30, 18, 30, 130), child: Column(
            children: [
              Align(alignment: Alignment.centerLeft,
                child: Material(color: Colors.white, shape: const CircleBorder(), elevation: 4,
                  child: IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF071E52)), iconSize: 25))),
              const SizedBox(height: 8),
              const Text('Rezervasyonlar', style: TextStyle(fontSize: 24,
                fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
              const SizedBox(height: 29),
              _buildMenuCard(
                context,
                icon: Icons.book_rounded,
                title: "Kitap Ver",
                subtitle: "Öğrenciye kitap ödünç ver",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LoanBookPage(schoolCode: schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: Icons.assignment_return_rounded,
                title: "İade Al",
                subtitle: "Ödünç alınan kitabı iade al",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReturnBookPage(schoolCode: schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: Icons.event_note_rounded,
                title: "Rezervasyonlar",
                subtitle: "Tüm rezervasyon geçmişi",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ReservationListPage(schoolCode: schoolCode),
                    ),
                  );
                },
              ),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF9FCFF),
      borderRadius: BorderRadius.circular(19),
      elevation: 5,
      shadowColor: const Color(0x285B9BD9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: ClipRRect(borderRadius: BorderRadius.circular(19), child: Container(
          width: double.infinity,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x285B9BD9), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Stack(children: [
            Positioned(bottom: -42, left: -35, child: Container(width: 240, height: 90,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE1F1FF)))),
            Positioned(bottom: -55, right: -35, child: Container(width: 250, height: 98,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC6E5FF)))),
            Positioned(bottom: -70, left: 0, child: Container(width: 360, height: 88,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFD4EAFF)))),
            Positioned.fill(child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFFDFEFFF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: const Color(0xFF286FCB), size: 43),
              ),
              const SizedBox(height: 7),
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                color: Color(0xFF071E52))),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF536C96))),
            ],
          )),
          Positioned(right: 14, top: 65, child: Container(width: 39, height: 39,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: const Icon(Icons.chevron_right_rounded, color: Color(0xFF071E52), size: 29))),
          ]),
        )),
      ),
    );
  }
}
