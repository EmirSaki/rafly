import 'package:flutter/material.dart';
import 'scanner_page.dart';
import 'manuel_book_page.dart';

class AddBookPage extends StatelessWidget {
  final String schoolCode;
  const AddBookPage({super.key, required this.schoolCode});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FBFF),
    body: SafeArea(child: Stack(children: [
      Positioned(bottom: -125, left: -100, child: Container(width: 540, height: 250,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC1DCFA)))),
      Positioned(bottom: -155, left: -120, child: Container(width: 540, height: 245,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF70B1F0)))),
      Positioned(bottom: -185, left: -125, child: Container(width: 530, height: 245,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2878CA)))),
      SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 130),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Material(color: Colors.white, shape: const CircleBorder(), elevation: 4,
              child: IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF09255A)), iconSize: 29)),
            const SizedBox(width: 12),
            const Text('Kitap Ekleme', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF09255A))),
          ]),
          const SizedBox(height: 52),
          Center(child: Container(width: 185, height: 130,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE5F1FF)),
            child: const Icon(Icons.auto_stories_rounded, size: 103, color: Color(0xFF3184E5)))),
          const SizedBox(height: 14),
          const Text('Kitap Ekleme', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
          const SizedBox(height: 7),
          const Text('Kütüphanenize kitap eklemek için\nbir yöntem seçin.', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF69758E))),
          const SizedBox(height: 42),
          _OptionCard(icon: Icons.qr_code_scanner_rounded, title: 'Barkod Okutma',
            subtitle: 'Kitabın ISBN barkodunu taratarak ekle.',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ScannerPage(schoolCode: schoolCode)))),
          const SizedBox(height: 15),
          _OptionCard(icon: Icons.edit_rounded, title: 'Manuel Ekleme',
            subtitle: 'ISBN numarası ile kitap bilgilerini getir.',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ManualBookPage(schoolCode: schoolCode)))),
        ])),
    ])),
  );
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _OptionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white, borderRadius: BorderRadius.circular(20),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x141D60A5), blurRadius: 22, offset: Offset(0, 8))]),
        child: Row(children: [
          Container(width: 82, height: 82,
            decoration: BoxDecoration(color: const Color(0xFFDEECFF), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, size: 42, color: const Color(0xFF1C63BC))),
          const SizedBox(width: 17),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF071E52))),
            const SizedBox(height: 7),
            Text(subtitle, style: const TextStyle(fontSize: 13, height: 1.35, color: Color(0xFF69758E))),
          ])),
          const SizedBox(width: 9),
          Container(width: 39, height: 39,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE9F3FF)),
            child: const Icon(Icons.chevron_right_rounded, size: 30, color: Color(0xFF09255A))),
        ]),
      ),
    ),
  );
}
