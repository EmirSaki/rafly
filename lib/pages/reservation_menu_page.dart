import 'package:flutter/material.dart';
import '../main.dart';
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
      appBar: AppBar(title: const Text("Rezervasyonlar")),
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "İşlem Seçin",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.book_outlined,
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
              const SizedBox(height: 10),
              _buildMenuCard(
                context,
                icon: Icons.assignment_return_outlined,
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
              const SizedBox(height: 10),
              _buildMenuCard(
                context,
                icon: Icons.list_alt_outlined,
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
          ),
        ),
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
      color: kSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(fontSize: 13, color: kTextSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
