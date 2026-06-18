import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';

class StudentReservationHistoryPage extends StatefulWidget {
  final String schoolCode;
  final Map<String, dynamic> student;

  const StudentReservationHistoryPage({
    super.key,
    required this.schoolCode,
    required this.student,
  });

  @override
  State<StudentReservationHistoryPage> createState() =>
      _StudentReservationHistoryPageState();
}

class _StudentReservationHistoryPageState
    extends State<StudentReservationHistoryPage> {
  bool isLoading = true;
  bool isDeleting = false;
  String errorMessage = "";
  List<Map<String, dynamic>> reservations = [];

  @override
  void initState() {
    super.initState();
    loadStudentReservations();
  }

  Future<void> loadStudentReservations() async {
    final studentNumber =
        widget.student["student_number"]?.toString().trim() ?? "";
    final schoolLevel =
        widget.student["school_level"]?.toString().trim() ?? "";

    try {
      setState(() {
        isLoading = true;
        errorMessage = "";
        reservations = [];
      });

      final allResults = await ApiService.getReservations(
        schoolCode: widget.schoolCode,
        studentNumber: studentNumber,
      );

      final filtered = schoolLevel.isEmpty
          ? allResults
          : allResults.where((item) {
              final itemLevel =
                  item["school_level"]?.toString().trim().toLowerCase() ?? "";
              return itemLevel == schoolLevel.toLowerCase();
            }).toList();

      filtered.sort((a, b) {
        final aDate = DateTime.tryParse(a["due_date"]?.toString() ?? "") ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b["due_date"]?.toString() ?? "") ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() => reservations = filtered);
    } catch (e) {
      if (!mounted) return;
      setState(
          () => errorMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String twoDigits(int value) => value.toString().padLeft(2, "0");

  String formatDateTime(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty || raw == "null") return "-";
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return "${twoDigits(local.day)}.${twoDigits(local.month)}.${local.year} ${twoDigits(local.hour)}.${twoDigits(local.minute)}";
  }

  Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case "loaned": return kWarning;
      case "returned": return kSuccess;
      default: return kTextSecondary;
    }
  }

  String statusText(String status) {
    switch (status.toLowerCase()) {
      case "loaned": return "Ödünçte";
      case "returned": return "İade Edildi";
      default: return status.isEmpty ? "-" : status;
    }
  }

  Future<void> _confirmAndDeleteStudent() async {
    final fullName = widget.student["full_name"]?.toString() ?? "Bu öğrenci";
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Öğrenci Sil"),
        content: Text("\"$fullName\" adlı öğrenciyi silmek istediğinize emin misiniz?\n\nBu işlem geri alınamaz."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Vazgeç"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: kDestructive),
            child: const Text("Sil"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final studentNumber = widget.student["student_number"]?.toString().trim() ?? "";
    final schoolLevel = widget.student["school_level"]?.toString().trim() ?? "";

    setState(() => isDeleting = true);
    try {
      await ApiService.deleteStudent(
        schoolCode: widget.schoolCode,
        studentNumber: studentNumber,
        schoolLevel: schoolLevel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Öğrenci silindi"), backgroundColor: kSuccess),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Hata: ${e.toString().replaceFirst('Exception: ', '')}"),
          backgroundColor: kDestructive,
        ),
      );
    } finally {
      if (mounted) setState(() => isDeleting = false);
    }
  }

  Widget buildStudentHeader() {
    final fullName = widget.student["full_name"]?.toString() ?? "-";
    final studentNumber =
        widget.student["student_number"]?.toString() ?? "-";
    final className = widget.student["class_name"]?.toString() ?? "-";
    final schoolLevel = widget.student["school_level"]?.toString() ?? "-";

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fullName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text("No: $studentNumber · Sınıf: $className · $schoolLevel",
              style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Toplam işlem: ${reservations.length}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kPrimary,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildReservationCard(Map<String, dynamic> item) {
    final status = item["status"]?.toString() ?? "";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item["book_name"]?.toString() ?? "Kitap",
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText(status),
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text("ISBN: ${item["isbn"] ?? "-"}",
              style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          const Divider(height: 14),
          Text(
            "İade tarihi: ${formatDateTime(item["due_date"])}",
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kTextPrimary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentName =
        widget.student["full_name"]?.toString() ?? "Öğrenci";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Öğrenci Geçmişi"),
        actions: [
          IconButton(
            onPressed: isLoading ? null : loadStudentReservations,
            icon: const Icon(Icons.refresh),
            tooltip: "Yenile",
          ),
        ],
      ),
      backgroundColor: kBackground,
      body: Column(
        children: [
          buildStudentHeader(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: kDestructive,
                                  fontWeight: FontWeight.w500)),
                        ),
                      )
                    : reservations.isEmpty
                        ? Center(
                            child: Text(
                              "$studentName için rezervasyon geçmişi bulunamadı",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 14, color: kTextSecondary),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: loadStudentReservations,
                            child: ListView.builder(
                              padding: EdgeInsets.only(
                                top: 6,
                                bottom:
                                    MediaQuery.of(context).padding.bottom + 20,
                              ),
                              itemCount: reservations.length,
                              itemBuilder: (context, index) {
                                return buildReservationCard(
                                    reservations[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
