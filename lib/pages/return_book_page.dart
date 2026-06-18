import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../main.dart';

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
      );

      final filtered = allLoaned.where((item) {
        return item["student_number"]?.toString() == studentNumber &&
            item["school_level"]?.toString() == selectedLevel;
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
      await loadStudentLoans();
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
                Text("Sınıf: ${item["class_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
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
      appBar: AppBar(title: const Text("İade Al")),
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Okul Seviyesi",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedLevel,
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
                  const SizedBox(height: 12),
                  const Text("Öğrenci Numarası",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: studentNumberController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : loadStudentLoans,
                      child: isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Aktif Ödünçleri Getir"),
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
                  ? const Center(
                      child: Text("Liste boş", style: TextStyle(fontSize: 14, color: kTextSecondary)),
                    )
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
      ),
    );
  }
}
