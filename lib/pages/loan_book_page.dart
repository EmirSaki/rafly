import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'isbn_scan_page.dart';

class LoanBookPage extends StatefulWidget {
  final String schoolCode;

  const LoanBookPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<LoanBookPage> createState() => _LoanBookPageState();
}

class _LoanBookPageState extends State<LoanBookPage> {
  final TextEditingController isbnController = TextEditingController();
  final TextEditingController studentNumberController = TextEditingController();
  DateTime loanDate = DateTime.now();
  DateTime? dueDate;

  String selectedLevel = "ortaokul";
  bool isLoading = false;
  bool isLoaning = false;
  String statusMessage = "";

  Map<String, dynamic>? bookPreview;
  Map<String, dynamic>? lastLoan;

  final List<Map<String, String>> schoolLevels = const [
    {"value": "ilkokul", "label": "İlkokul"},
    {"value": "ortaokul", "label": "Ortaokul"},
    {"value": "lise", "label": "Lise"},
    {"value": "hazırlık", "label": "Hazırlık"},
    {"value": "diğer", "label": "Diğer"},
  ];

  @override
  void initState() {
    super.initState();
    loanDate = DateTime.now();
    dueDate = loanDate.add(const Duration(days: 15));
  }

  @override
  void dispose() {
    isbnController.dispose();
    studentNumberController.dispose();
    super.dispose();
  }

  String twoDigits(int value) => value.toString().padLeft(2, "0");

  String formatDateTimeForView(DateTime value) {
    return "${twoDigits(value.day)}.${twoDigits(value.month)}.${value.year}";
  }

  Future<void> pickDueDate() async {
    if (isLoading || isLoaning) return;
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (selectedDate == null || !mounted) return;
    setState(() {
      dueDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    });
  }

  String formatReservationDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty || raw == "null") return "-";
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return formatDateTimeForView(parsed);
  }

  Future<void> scanIsbnAndFetchBook() async {
    if (isLoading || isLoaning) return;
    final scannedIsbn = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const IsbnScanPage()),
    );
    if (!mounted) return;
    final isbn = ApiService.normalizeIsbn(scannedIsbn ?? "");
    if (isbn.isEmpty) return;
    setState(() {
      isbnController.text = isbn;
      bookPreview = null;
      lastLoan = null;
      statusMessage = "Barkod okundu. Kitap getiriliyor...";
    });
    await fetchBookPreview();
  }

  Future<void> fetchBookPreview() async {
    final isbn = ApiService.normalizeIsbn(isbnController.text);
    if (isbn.isEmpty) {
      setState(() { statusMessage = "ISBN boş olamaz"; bookPreview = null; });
      return;
    }
    if (isbn.length != 10 && isbn.length != 13) {
      setState(() { statusMessage = "ISBN 10 ya da 13 haneli olmalı"; bookPreview = null; });
      return;
    }

    try {
      FocusScope.of(context).unfocus();
      setState(() {
        isLoading = true;
        statusMessage = "Kitap aranıyor...";
        bookPreview = null;
        lastLoan = null;
      });

      final data = await ApiService.fetchSchoolBookByIsbn(
        schoolCode: widget.schoolCode,
        isbn: isbn,
      );
      if (!mounted) return;

      isbnController.text = ApiService.normalizeIsbn((data["isbn"] ?? isbn).toString());
      setState(() { bookPreview = data; statusMessage = "Kitap bulundu"; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        bookPreview = null;
        statusMessage = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String statusText(String status) {
    switch (status.toLowerCase()) {
      case "loaned": return "Ödünçte";
      case "returned": return "İade Edildi";
      default: return status.isEmpty ? "-" : status;
    }
  }

  /// Seçilen seviyedeki AKTİF öğrenciler içinde numarayı arar.
  /// Öğrenci yoksa boş map, liste alınamadıysa null döner.
  Future<Map<String, dynamic>?> findStudentInSelectedLevel(String studentNumber) async {
    try {
      final students = await ApiService.getStudents(
        schoolCode: widget.schoolCode,
        schoolLevel: selectedLevel,
      );
      final matched = students.where((s) =>
          s["student_number"]?.toString().trim() == studentNumber).toList();
      if (matched.isEmpty) return <String, dynamic>{};
      return matched.first;
    } catch (_) {
      return null;
    }
  }

  String get selectedLevelLabel => schoolLevels
      .firstWhere((l) => l["value"] == selectedLevel, orElse: () => {"label": selectedLevel})["label"]!;

  Future<bool> showLoanConfirmDialog({
    required String bookName,
    required String studentNumber,
    required String studentName,
    required String studentClass,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Rezervasyon Onayı"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Bu rezervasyonu onaylıyor musunuz?"),
              const SizedBox(height: 14),
              Text("Kitap: $bookName", style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text("Öğrenci No: $studentNumber"),
              const SizedBox(height: 6),
              Text("Öğrenci Adı: $studentName"),
              const SizedBox(height: 6),
              Text("Sınıf: $studentClass · $selectedLevelLabel"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Hayır"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Evet"),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> loanBook() async {
    final isbn = ApiService.normalizeIsbn(isbnController.text);
    final studentNumber = studentNumberController.text.trim();

    if (bookPreview == null) {
      setState(() => statusMessage = "Önce ISBN ile kitabı getir");
      return;
    }
    if (isbn.isEmpty) {
      setState(() => statusMessage = "ISBN boş olamaz");
      return;
    }

    final availableQuantity = int.tryParse(
      '${bookPreview?["available_quantity"] ?? bookPreview?["availableQuantity"] ?? 0}',
    ) ?? 0;

    if (availableQuantity <= 0) {
      setState(() => statusMessage = "Bu kitap stokta yok");
      return;
    }
    if (studentNumber.isEmpty) {
      setState(() => statusMessage = "Öğrenci numarası boş olamaz");
      return;
    }

    FocusScope.of(context).unfocus();

    final bookName = bookPreview?["title"]?.toString().trim().isNotEmpty == true
        ? bookPreview!["title"].toString()
        : "Kitap";

    setState(() { isLoading = true; statusMessage = "Öğrenci bilgisi kontrol ediliyor..."; });
    final student = await findStudentInSelectedLevel(studentNumber);
    if (!mounted) return;
    setState(() { isLoading = false; statusMessage = ""; });

    // Numara başka seviyede (ya da mezun bir öğrencide) olsa bile, seçilen
    // seviyede aktif öğrenci yoksa işlem yapılmaz.
    if (student != null && student.isEmpty) {
      setState(() => statusMessage =
          "$selectedLevelLabel seviyesinde $studentNumber numaralı aktif öğrenci yok. Okul seviyesini kontrol et.");
      return;
    }
    final studentName = student?["full_name"]?.toString() ?? "-";
    final studentClass = student?["class_name"]?.toString() ?? "-";

    final confirmed = await showLoanConfirmDialog(
      bookName: bookName,
      studentNumber: studentNumber,
      studentName: studentName,
      studentClass: studentClass,
    );
    if (!mounted) return;

    if (!confirmed) {
      setState(() => statusMessage = "Rezervasyon iptal edildi");
      return;
    }

    try {
      setState(() {
        isLoaning = true;
        statusMessage = "Kitap öğrenciye veriliyor...";
        lastLoan = null;
      });

      final result = await ApiService.loanBookByStudent(
        schoolCode: widget.schoolCode,
        isbn: isbn,
        studentNumber: studentNumber,
        schoolLevel: selectedLevel,
        dueDate: dueDate!.toIso8601String(),
      );
      if (!mounted) return;

      setState(() {
        lastLoan = Map<String, dynamic>.from(result["data"] ?? {});
        statusMessage = result["message"] ?? "Kitap öğrenciye verildi";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => isLoaning = false);
    }
  }

  void clearForm() {
    FocusScope.of(context).unfocus();
    setState(() {
      isbnController.clear();
      studentNumberController.clear();
      loanDate = DateTime.now();
      dueDate = loanDate.add(const Duration(days: 15));
      selectedLevel = "ortaokul";
      statusMessage = "";
      bookPreview = null;
      lastLoan = null;
    });
  }

  Widget _buildBookPreviewCard() {
    final data = bookPreview;
    if (data == null) return const SizedBox.shrink();

    final title = data["title"]?.toString().trim();
    final publisher = data["publisher"]?.toString().trim();
    final isbn = data["isbn"]?.toString().trim();
    final quantity = int.tryParse('${data["quantity"] ?? 0}') ?? 0;
    final availableQuantity = int.tryParse(
      '${data["available_quantity"] ?? data["availableQuantity"] ?? 0}',
    ) ?? 0;
    final isOutOfStock = availableQuantity <= 0;
    final authors = ApiService.normalizeStringList(data["authors"]);
    final authorsText = authors.isNotEmpty ? authors.join(", ") : "Bilinmiyor";

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOutOfStock ? kDestructive.withValues(alpha: 0.05) : kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOutOfStock ? kDestructive.withValues(alpha: 0.3) : kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Kitap Bilgisi",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOutOfStock
                      ? kDestructive.withValues(alpha: 0.08)
                      : kSuccess.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Mevcut: $availableQuantity / $quantity",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isOutOfStock ? kDestructive : kSuccess,
                  ),
                ),
              ),
            ],
          ),
          if (isOutOfStock) ...[
            const SizedBox(height: 6),
            Text("Bu kitap şu an stokta yok",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kDestructive)),
          ],
          const SizedBox(height: 10),
          Text(title != null && title.isNotEmpty ? title : "-",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kTextPrimary)),
          const SizedBox(height: 4),
          Text("Yazar: $authorsText", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Yayınevi: ${publisher != null && publisher.isNotEmpty ? publisher : "Bilinmiyor"}",
              style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("ISBN: ${isbn != null && isbn.isNotEmpty ? isbn : "-"}",
              style: const TextStyle(fontSize: 13, color: kTextSecondary)),
        ],
      ),
    );
  }

  Widget _buildLastLoanCard() {
    final data = lastLoan;
    if (data == null) return const SizedBox.shrink();

    final student = Map<String, dynamic>.from(data["student"] ?? {});
    final book = Map<String, dynamic>.from(data["book"] ?? {});
    final reservation = Map<String, dynamic>.from(data["reservation"] ?? {});

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSuccess.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kSuccess.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Son İşlem",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary)),
          const SizedBox(height: 8),
          Text("Kitap: ${book["book_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Yazar: ${book["book_writer"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("ISBN: ${book["isbn"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          const Divider(height: 16),
          Text("Öğrenci: ${student["full_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Numara: ${student["student_number"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Sınıf: ${student["class_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Seviye: ${student["school_level"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          const Divider(height: 16),
          Text("Durum: ${statusText(reservation["status"]?.toString() ?? "")}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("İade tarihi: ${formatReservationDate(reservation["due_date"])}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
        ],
      ),
    );
  }

  Widget _fieldHeader(IconData icon, String title, String hint) => Row(children: [
    Container(width: 43, height: 43,
      decoration: BoxDecoration(color: const Color(0xFFE2F2FF), borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, color: const Color(0xFF0D3C9A), size: 24)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: Color(0xFF071E52))),
      Text(hint, style: const TextStyle(fontSize: 11, color: Color(0xFF71809A))),
    ])),
  ]);

  @override
  Widget build(BuildContext context) {
    final busy = isLoading || isLoaning;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        backgroundColor: const Color(0xFFEEF7FF),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 72,
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: Material(
          color: Colors.white, shape: const CircleBorder(), elevation: 4,
          child: IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF09275F))))),
        centerTitle: true,
        title: const Text('Kitap Ver', style: TextStyle(fontSize: 23,
          fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: Material(
            color: Colors.white, shape: const CircleBorder(), elevation: 4,
            child: IconButton(
            onPressed: busy ? null : clearForm,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1238C9)),
            tooltip: "Temizle",
          ))),
        ],
      ),
      backgroundColor: const Color(0xFFEEF7FF),
      body: SafeArea(
        child: Stack(children: [
          Positioned(bottom: -135, left: -110, child: Container(width: 560, height: 260,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFBBDEFC)))),
          Positioned(bottom: -167, left: -110, child: Container(width: 560, height: 250,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF70B2F0)))),
          Positioned(bottom: -200, left: -115, child: Container(width: 560, height: 240,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2D82D6)))),
          SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 125),
          child: Container(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          decoration: BoxDecoration(color: const Color(0xFFFAFCFF),
            borderRadius: BorderRadius.circular(19), border: Border.all(color: Colors.white),
            boxShadow: const [BoxShadow(color: Color(0x295C9DD9), blurRadius: 18, offset: Offset(0, 8))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldHeader(Icons.view_week_rounded, 'ISBN', 'Kitabın ISBN numarasını girin'),
              const SizedBox(height: 8),
              TextField(
                controller: isbnController,
                enabled: !busy,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: "9786258400069",
                  filled: true, fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: Color(0xFFE1E8F3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: Color(0xFF7AB7F1), width: 1.5)),
                  suffixIcon: IconButton(
                    tooltip: "Barkod tara",
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    onPressed: busy ? null : scanIsbnAndFetchBook,
                  ),
                ),
                onChanged: (_) {
                  if (bookPreview != null || lastLoan != null) {
                    setState(() { bookPreview = null; lastLoan = null; statusMessage = ""; });
                  }
                },
                onSubmitted: (_) { if (!busy) fetchBookPreview(); },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 49,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : fetchBookPreview,
                  style: OutlinedButton.styleFrom(backgroundColor: const Color(0xFFD9EAFE),
                    foregroundColor: const Color(0xFF092A73),
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: isLoading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search_rounded, size: 23),
                  label: Text(isLoading ? "Kitap Aranıyor..." : "Kitabı Getir",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              _buildBookPreviewCard(),
              const SizedBox(height: 16),
              const Divider(height: 30, color: Color(0xFFE7EFF9)),
              _fieldHeader(Icons.school_outlined, 'Okul Seviyesi', 'Öğrencinin okul seviyesini seçin'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedLevel,
                decoration: InputDecoration(filled: true, fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: Color(0xFFE1E8F3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: Color(0xFF7AB7F1), width: 1.5))),
                items: schoolLevels.map((level) {
                  return DropdownMenuItem<String>(
                    value: level["value"],
                    child: Text(level["label"]!),
                  );
                }).toList(),
                onChanged: busy ? null : (value) {
                  if (value == null) return;
                  setState(() => selectedLevel = value);
                },
              ),
              const SizedBox(height: 14),
              const Divider(height: 30, color: Color(0xFFE7EFF9)),
              _fieldHeader(Icons.person_outline_rounded, 'Öğrenci Numarası', 'Öğrenci numarasını girin'),
              const SizedBox(height: 8),
              TextField(
                controller: studentNumberController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(hintText: "1001", filled: true, fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: Color(0xFFE1E8F3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: Color(0xFF7AB7F1), width: 1.5))),
              ),
              const SizedBox(height: 14),
              const Divider(height: 30, color: Color(0xFFE7EFF9)),
              _fieldHeader(Icons.calendar_month_outlined, 'İade Tarihi', 'Tahmini iade tarihini seçin'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: busy ? null : pickDueDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFFE1E8F3)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        dueDate != null ? formatDateTimeForView(dueDate!) : "Tarih seçin",
                        style: TextStyle(
                          fontSize: 14,
                          color: dueDate != null ? kTextPrimary : kTextSecondary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.calendar_month_outlined, size: 20, color: Color(0xFF173A83)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: busy ? null : loanBook,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0754BD),
                    foregroundColor: Colors.white, elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: isLoaning
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.check_circle, size: 22), SizedBox(width: 9),
                          Flexible(child: Text('Kitabı Öğrenciye Ver',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                          SizedBox(width: 6), Icon(Icons.chevron_right_rounded, size: 24)]),
                ),
              ),
              if (statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(statusMessage,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextSecondary)),
                ),
              _buildLastLoanCard(),
            ],
          ),
          ),
        ),
        ]),
      ),
    );
  }
}
