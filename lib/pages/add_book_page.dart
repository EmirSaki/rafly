import 'package:flutter/material.dart';
import '../main.dart';
import 'scanner_page.dart';
import 'manuel_book_page.dart';

class AddBookPage extends StatelessWidget {
  final String schoolCode;

  const AddBookPage({
    super.key,
    required this.schoolCode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Kitap Ekleme")),
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Ekleme Yöntemi",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Kitap eklemek için bir yöntem seçin",
                style: TextStyle(fontSize: 13, color: kTextSecondary),
              ),
              const SizedBox(height: 20),
              _buildOptionCard(
                context,
                icon: Icons.qr_code_scanner,
                title: "Barkod Okutma",
                subtitle: "Kitabın ISBN barkodunu taratarak ekle",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScannerPage(schoolCode: schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  "veya",
                  style: TextStyle(
                    fontSize: 13,
                    color: kTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildOptionCard(
                context,
                icon: Icons.edit_outlined,
                title: "Manuel Ekleme",
                subtitle: "ISBN numarası ile kitap bilgilerini getir",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManualBookPage(schoolCode: schoolCode),
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

  Widget _buildOptionCard(
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: kPrimary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: kTextSecondary),
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
