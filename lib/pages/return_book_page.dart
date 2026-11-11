import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'isbn_scan_page.dart';

class ReturnBookPage extends StatefulWidget {
  final String schoolCode;

  const ReturnBookPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<ReturnBookPage> createState() => _ReturnBookPageState();
}

class _ReturnBookPageState extends State<ReturnBookPage> {
  final TextEditingController studentNumberController = TextEditingController();

  String selectedLevel = "ortaokul";
  bool isLoading = false;
  String statusMessage = "";
  List<Map<String, dynamic>> reservations = [];
  String? _lastScannedIsbn;

  final List<Map<String, String>> schoolLevels = const [
    {"value": "ilkokul", "label": "İlkokul"},
    {"value": "ortaokul", "label": "Ortaokul"},
    {"value": "lise", "label": "Lise"},
    {"value": "hazırlık", "label": "Hazırlık"},
    {"value": "diğer", "label": "Diğer"},
  ];

  @override
  void dispose() {
    studentNumberController.dispose();
    super.dispose();
  }

  String formatDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty || raw == "null") return "-";
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return "${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}";
  }

  Future<void> loadStudentLoans() async {
    _lastScannedIsbn = null;
    final studentNumber = studentNumberController.text.trim();
    if (studentNumber.isEmpty) {
      setState(() => statusMessage = "Öğrenci numarası gir");
      return;
    }

    try {
      setState(() {
        isLoading = true;
        statusMessage = "Aktif ödünçler getiriliyor...";
        reservations = [];
      });

      final allLoaned = await ApiService.getReservations(
        schoolCode: widget.schoolCode,
        status: "loaned",
        studentNumber: studentNumber,
        schoolLevel: selectedLevel,
      );

      // Numara + seviye birlikte eşleşmeli; yalnızca numarası tutan başka
      // seviyedeki öğrencinin ödünçleri listelenmez.
      final filtered = allLoaned.where((item) {
        return item["student_number"]?.toString().trim() == studentNumber &&
            (item["school_level"]?.toString().trim().toLowerCase() ?? "") ==
                selectedLevel.toLowerCase();
      }).toList();

      if (!mounted) return;

      setState(() {
        reservations = filtered;
        statusMessage = filtered.isEmpty
            ? "Bu öğrenciye ait aktif ödünç bulunamadı"
            : "${filtered.length} aktif ödünç bulundu";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> scanBookLoans() async {
    if (isLoading) return;
    final isbn = await Navigator.push<String>(context,
      MaterialPageRoute(builder: (_) => const IsbnScanPage()));
    if (!mounted || isbn == null) return;
    _lastScannedIsbn = isbn;
    await _loadBookLoansForIsbn(isbn);
  }

  Future<void> _loadBookLoansForIsbn(String isbn) async {
    try {
      setState(() { isLoading = true; statusMessage = 'Aktif ödünçler getiriliyor...'; reservations = []; });
      final allLoaned = await ApiService.getReservations(
        schoolCode: widget.schoolCode, status: 'loaned');
      if (!mounted) return;
      final found = allLoaned.where((item) =>
        ApiService.normalizeIsbn(item['isbn']?.toString() ?? '') == isbn).toList();
      setState(() {
        reservations = found;
        statusMessage = found.isEmpty ? 'Bu ISBN için aktif ödünç bulunamadı' : '${found.length} aktif ödünç bulundu';
      });
    } catch (e) {
      if (mounted) setState(() => statusMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> returnBook(Map<String, dynamic> item) async {
    final id = int.tryParse(item["reservation_id"].toString());
    if (id == null) {
      setState(() => statusMessage = "Rezervasyon kimliği bulunamadı");
      return;
    }

    try {
      setState(() {
        isLoading = true;
        statusMessage = "İade alınıyor...";
      });

      final result = await ApiService.returnReservation(
        schoolCode: widget.schoolCode,
        reservationId: id,
      );

      if (!mounted) return;

      final successMessage = result["message"] ?? "Kitap iade alındı";
      if (_lastScannedIsbn != null) {
        await _loadBookLoansForIsbn(_lastScannedIsbn!);
      } else {
        await loadStudentLoans();
      }
      if (!mounted) return;
      setState(() => statusMessage = successMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Widget buildReservationCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["book_name"]?.toString() ?? "Kitap",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary),
                ),
                const SizedBox(height: 4),
                Text("ISBN: ${item["isbn"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                Text("Öğrenci: ${item["student_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                Text(
                  "Sınıf: ${item["class_name"] ?? "-"} · ${item["school_level"] ?? "-"}"
                  "${item["student_archived_at"] != null ? " · Eski öğrenci" : ""}",
                  style: const TextStyle(fontSize: 13, color: kTextSecondary),
                ),
                Text("İade tarihi: ${formatDate(item["due_date"])}",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextPrimary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isLoading ? null : () => returnBook(item),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text("İade Al"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 74,
        backgroundColor: const Color(0xFFEDF6FF),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 70,
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: Material(
          color: Colors.white, shape: const CircleBorder(), elevation: 4,
          child: IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0962D4))))),
        title: const Text('İade Al', style: TextStyle(fontSize: 22,
          fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Material(
          color: Colors.white, borderRadius: BorderRadius.circular(13), elevation: 3,
          child: IconButton(tooltip: 'Kitap barkodu tara', onPressed: scanBookLoans,
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF247EEC)))))]),
      backgroundColor: const Color(0xFFEDF6FF),
      body: SafeArea(
        child: Stack(children: [
          Positioned(bottom: -135, left: -105, child: Container(width: 560, height: 220,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE0F0FF)))),
          Positioned(bottom: -168, left: -115, child: Container(width: 560, height: 220,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC7E3FF)))),
          Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x1B6196D4), blurRadius: 17, offset: Offset(0, 5))]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [CircleAvatar(backgroundColor: const Color(0xFFE3F0FF),
                    child: const Icon(Icons.school_rounded, color: Color(0xFF2178E8))),
                    const SizedBox(width: 10), const Text('Okul Seviyesi',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF071E52)))]),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedLevel,
                    decoration: InputDecoration(filled: true, fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.account_balance_outlined, color: Color(0xFF7D9BCD)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2EAF4))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF85B9F1)))),
                    items: schoolLevels.map((level) {
                      return DropdownMenuItem<String>(
                        value: level["value"],
                        child: Text(level["label"]!),
                      );
                    }).toList(),
                    onChanged: isLoading ? null : (value) {
                      if (value == null) return;
                      setState(() => selectedLevel = value);
                    },
                  ),
                    ])),
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x1B6196D4), blurRadius: 17, offset: Offset(0, 5))]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [CircleAvatar(backgroundColor: const Color(0xFFE3F0FF),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF2178E8))),
                    const SizedBox(width: 10), const Text('Öğrenci Numarası',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF071E52)))]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: studentNumberController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(hintText: 'Öğrenci numarasını girin...',
                      prefixIcon: const Icon(Icons.tag_rounded, color: Color(0xFF7D9BCD)),
                      filled: true, fillColor: Colors.white,
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2EAF4))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF85B9F1)))),
                  ),
                    ])),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : loadStudentLoans,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0866E3),
                        foregroundColor: Colors.white, elevation: 5,
                        shape: const StadiumBorder()),
                      child: isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.keyboard_return_rounded, size: 22), SizedBox(width: 10),
                              Text('Aktif Ödünçleri Getir', style: TextStyle(fontWeight: FontWeight.w700))]),
                    ),
                  ),
                  if (statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(statusMessage, style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: reservations.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 140, height: 120,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE4F0FF)),
                        child: const Icon(Icons.library_books_outlined, size: 75, color: Color(0xFF95BCF4))),
                      const SizedBox(height: 14),
                      const Text('Liste boş', style: TextStyle(fontSize: 21,
                        fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
                      const SizedBox(height: 8),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: Text(
                        'Seçilen öğrenciye ait iade edilecek\naktif ödünç bulunamadı.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 14,
                          height: 1.45, color: Color(0xFF687EA7)))),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: reservations.length,
                      itemBuilder: (context, index) {
                        return buildReservationCard(reservations[index]);
                      },
                    ),
            ),
          ],
          ),
        ]),
      ),
    );
  }
}
