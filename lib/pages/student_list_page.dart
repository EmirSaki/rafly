import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'student_reservation_history_page.dart';

class StudentListPage extends StatefulWidget {
  final String schoolCode;

  const StudentListPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<StudentListPage> createState() => _StudentListPageState();
}

class _StudentListPageState extends State<StudentListPage> {
  bool isLoading = true;
  String errorMessage = "";
  String selectedLevel = "tümü";

  List<Map<String, dynamic>> students = [];

  bool isUploading = false;
  String uploadMessage = "";

  bool isAddingStudent = false;

  Map<String, String> loanedStudents = {};
  Set<String> overdueStudents = {};

  final TextEditingController studentNumberController = TextEditingController();
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController classNameController = TextEditingController();

  String addStudentLevel = "ortaokul";

  final List<Map<String, String>> schoolLevels = const [
    {"value": "tümü", "label": "Tümü"},
    {"value": "ilkokul", "label": "İlkokul"},
    {"value": "ortaokul", "label": "Ortaokul"},
    {"value": "lise", "label": "Lise"},
    {"value": "hazırlık", "label": "Hazırlık"},
    {"value": "diğer", "label": "Diğer"},
  ];

  @override
  void initState() {
    super.initState();
    loadStudents();
    loadLoanedStudents();
  }

  @override
  void dispose() {
    studentNumberController.dispose();
    fullNameController.dispose();
    classNameController.dispose();
    super.dispose();
  }

  int getClassNumber(String className) {
    final match = RegExp(r'\d+').firstMatch(className);
    if (match == null) return 999;
    return int.tryParse(match.group(0) ?? "") ?? 999;
  }

  String getClassBranch(String className) {
    final normalized = ApiService.normalizeTurkishText(className);
    final cleaned = normalized
        .replaceAll(RegExp(r'\d+'), '')
        .replaceAll(RegExp(r'[^a-z]'), '')
        .trim();
    return cleaned;
  }

  int compareStudentsByClassAndBranch(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aClassName = a["class_name"]?.toString() ?? "";
    final bClassName = b["class_name"]?.toString() ?? "";

    final aClassNumber = getClassNumber(aClassName);
    final bClassNumber = getClassNumber(bClassName);

    final numberCompare = aClassNumber.compareTo(bClassNumber);
    if (numberCompare != 0) return numberCompare;

    final aBranch = getClassBranch(aClassName);
    final bBranch = getClassBranch(bClassName);

    final branchCompare = aBranch.compareTo(bBranch);
    if (branchCompare != 0) return branchCompare;

    final aStudentNumber = int.tryParse('${a["student_number"] ?? ""}') ?? 999999999;
    final bStudentNumber = int.tryParse('${b["student_number"] ?? ""}') ?? 999999999;

    final studentNumberCompare = aStudentNumber.compareTo(bStudentNumber);
    if (studentNumberCompare != 0) return studentNumberCompare;

    final aName = ApiService.normalizeTurkishText(a["full_name"]?.toString() ?? "");
    final bName = ApiService.normalizeTurkishText(b["full_name"]?.toString() ?? "");

    return aName.compareTo(bName);
  }

  Future<void> loadLoanedStudents() async {
    try {
      final reservations = await ApiService.getReservations(
        schoolCode: widget.schoolCode,
        status: "loaned",
      );
      if (!mounted) return;
      final map = <String, String>{};
      final overdue = <String>{};
      final now = DateTime.now();
      for (final r in reservations) {
        final num = r["student_number"]?.toString().trim().replaceAll(RegExp(r'\s+'), '') ?? "";
        final level = r["school_level"]?.toString().trim().toLowerCase() ?? "";
        if (num.isNotEmpty) {
          map["${num}_$level"] = level;
          final dueDateStr = r["due_date"]?.toString();
          if (dueDateStr != null) {
            try {
              final due = DateTime.parse(dueDateStr);
              if (due.isBefore(DateTime(now.year, now.month, now.day))) {
                overdue.add("${num}_$level");
              }
            } catch (_) {}
          }
        }
      }
      setState(() {
        loanedStudents = map;
        overdueStudents = overdue;
      });
    } catch (_) {}
  }

  Future<void> loadStudents() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = "";
      });

      final result = await ApiService.getStudents(
        schoolCode: widget.schoolCode,
        schoolLevel: selectedLevel == "tümü" ? null : selectedLevel,
      );

      if (!mounted) return;

      result.sort(compareStudentsByClassAndBranch);
      setState(() => students = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  String _nextDigerNumber() {
    int max = 9999;
    for (final s in students) {
      final num = int.tryParse(s["student_number"]?.toString() ?? "") ?? 0;
      if (num >= 10000 && num > max) max = num;
    }
    return (max + 1).toString();
  }

  void showAddStudentDialog() {
    studentNumberController.clear();
    fullNameController.clear();
    classNameController.clear();
    addStudentLevel = selectedLevel == "tümü" ? "ortaokul" : selectedLevel;
    if (addStudentLevel == "diğer") {
      studentNumberController.text = _nextDigerNumber();
    }

    showDialog(
      context: context,
      barrierDismissible: !isAddingStudent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDiger = addStudentLevel == "diğer";
            return AlertDialog(
              title: const Text("Öğrenci Ekle"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isDiger ? "Öğrenci Numarası (Otomatik)" : "Öğrenci Numarası",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: studentNumberController,
                      keyboardType: TextInputType.number,
                      enabled: !isDiger,
                      decoration: InputDecoration(hintText: isDiger ? "" : "1001"),
                    ),
                    const SizedBox(height: 12),
                    const Text("Ad Soyad",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: fullNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: "Ali Yılmaz"),
                    ),
                    const SizedBox(height: 12),
                    const Text("Sınıf",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: classNameController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: "5A"),
                    ),
                    const SizedBox(height: 12),
                    const Text("Okul Seviyesi",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: addStudentLevel,
                      items: schoolLevels
                          .where((level) => level["value"] != "tümü")
                          .map((level) {
                        return DropdownMenuItem<String>(
                          value: level["value"],
                          child: Text(level["label"]!),
                        );
                      }).toList(),
                      onChanged: isAddingStudent
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                addStudentLevel = value;
                                if (value == "diğer") {
                                  studentNumberController.text = _nextDigerNumber();
                                } else {
                                  studentNumberController.clear();
                                }
                              });
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isAddingStudent ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text("Vazgeç"),
                ),
                ElevatedButton(
                  onPressed: isAddingStudent ? null : addManualStudent,
                  child: isAddingStudent
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("Kaydet"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> addManualStudent() async {
    final studentNumber = addStudentLevel == "diğer"
        ? _nextDigerNumber()
        : studentNumberController.text.trim();
    final fullName = fullNameController.text.trim();
    final className = classNameController.text.trim();

    if (studentNumber.isEmpty || fullName.isEmpty || className.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Öğrenci no, ad soyad ve sınıf zorunlu")),
      );
      return;
    }

    try {
      setState(() => isAddingStudent = true);

      final response = await ApiService.addManualStudent(
        schoolCode: widget.schoolCode,
        studentNumber: studentNumber,
        fullName: fullName,
        className: className,
        schoolLevel: addStudentLevel,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      studentNumberController.clear();
      fullNameController.clear();
      classNameController.clear();

      setState(() {
        selectedLevel = addStudentLevel;
        uploadMessage = response["message"]?.toString() ?? "Öğrenci eklendi";
      });

      await loadStudents();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response["message"]?.toString() ?? "Öğrenci eklendi")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (!mounted) return;
      setState(() => isAddingStudent = false);
    }
  }

  bool _sendingWarning = false;

  Future<void> _sendOverdueWarning(Map<String, dynamic> student) async {
    final fullName = student["full_name"]?.toString() ?? "";
    final studentNumber = student["student_number"]?.toString() ?? "";

    setState(() => _sendingWarning = true);
    try {
      final now = DateTime.now();
      final endDate = now.add(const Duration(days: 30));
      final startStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final endStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

      await ApiService.createAnnouncement(
        schoolCode: widget.schoolCode,
        title: "Kitap İade Uyarısı",
        content: "Sayın $fullName, aldığınız kitabın iade tarihi geçmiştir. Lütfen kitabınızı kütüphaneye iade edin.",
        targetType: "section",
        targetValues: [studentNumber],
        startDate: startStr,
        endDate: endStr,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Uyarı bildirimi gönderildi"),
          backgroundColor: kSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Hata: ${e.toString().replaceFirst('Exception: ', '')}"),
          backgroundColor: kDestructive,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingWarning = false);
    }
  }

  Widget buildStudentCard(Map<String, dynamic> student) {
    final studentNumber =
        student["student_number"]?.toString().trim().replaceAll(RegExp(r'\s+'), '') ?? "";
    final schoolLevel =
        student["school_level"]?.toString().trim().toLowerCase() ?? "";
    final key = "${studentNumber}_$schoolLevel";
    final isLoaned = loanedStudents.containsKey(key);
    final isOverdue = overdueStudents.contains(key);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final deleted = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => StudentReservationHistoryPage(
                  schoolCode: widget.schoolCode,
                  student: student,
                ),
              ),
            );
            if (deleted == true && mounted) {
              loadStudents();
              loadLoanedStudents();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isOverdue
                    ? kDestructive.withValues(alpha: 0.4)
                    : isLoaned
                        ? kWarning.withValues(alpha: 0.4)
                        : kBorder,
              ),
            ),
            child: Row(
              children: [
                if (isLoaned)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isOverdue
                            ? kDestructive.withValues(alpha: 0.1)
                            : kWarning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isOverdue ? Icons.warning_rounded : Icons.menu_book,
                        color: isOverdue ? kDestructive : kWarning,
                        size: 18,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student["full_name"]?.toString() ?? "-",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isOverdue ? kDestructive : isLoaned ? kWarning : kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "No: ${student["student_number"] ?? "-"} · Sınıf: ${student["class_name"] ?? "-"} · ${student["school_level"] ?? "-"}",
                        style: const TextStyle(fontSize: 12, color: kTextSecondary),
                      ),
                      if (isOverdue)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "İade tarihi geçmiş!",
                            style: TextStyle(
                              fontSize: 11,
                              color: kDestructive,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (isLoaned)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "Kitap ödünçte",
                            style: TextStyle(
                              fontSize: 11,
                              color: kWarning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isOverdue)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: _sendingWarning ? null : () => _sendOverdueWarning(student),
                        icon: _sendingWarning
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.notifications_active, size: 14),
                        label: const Text("Uyar", style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDestructive,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right, color: kTextSecondary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Öğrenci Listesi"),
        actions: [
          IconButton(
            onPressed: isLoading || isAddingStudent ? null : showAddStudentDialog,
            icon: const Icon(Icons.person_add_outlined),
            tooltip: "Öğrenci Ekle",
          ),
          IconButton(
            onPressed: isLoading ? null : loadStudents,
            icon: const Icon(Icons.refresh),
            tooltip: "Yenile",
          ),
        ],
      ),
      backgroundColor: kBackground,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                  onChanged: isLoading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => selectedLevel = value);
                          loadStudents();
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Text(errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: kDestructive, fontWeight: FontWeight.w500)),
                      )
                    : students.isEmpty
                        ? const Center(
                            child: Text("Öğrenci bulunamadı",
                                style: TextStyle(fontSize: 14, color: kTextSecondary)),
                          )
                        : RefreshIndicator(
                            onRefresh: loadStudents,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: students.length,
                              itemBuilder: (context, index) {
                                return buildStudentCard(students[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
