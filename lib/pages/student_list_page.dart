import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'student_reservation_history_page.dart';
import 'class_order.dart';

class StudentListPage extends StatefulWidget {
  final String schoolCode;

  const StudentListPage({super.key, required this.schoolCode});

  @override
  State<StudentListPage> createState() => _StudentListPageState();
}

class _StudentListPageState extends State<StudentListPage> {
  bool isLoading = true;
  String errorMessage = "";
  String selectedLevel = "tümü";
  String selectedClass = "tümü";
  String selectedTab = "students";
  String searchText = "";
  String? openClass;
  int page = 0;
  int pageSize = 10;

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

    final aStudentNumber =
        int.tryParse('${a["student_number"] ?? ""}') ?? 999999999;
    final bStudentNumber =
        int.tryParse('${b["student_number"] ?? ""}') ?? 999999999;

    final studentNumberCompare = aStudentNumber.compareTo(bStudentNumber);
    if (studentNumberCompare != 0) return studentNumberCompare;

    final aName = ApiService.normalizeTurkishText(
      a["full_name"]?.toString() ?? "",
    );
    final bName = ApiService.normalizeTurkishText(
      b["full_name"]?.toString() ?? "",
    );

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
        // Mezun/eski öğrencinin ödüncü, aynı numaralı aktif öğrenciye yazılmasın.
        if (r["student_archived_at"] != null) continue;
        final num =
            r["student_number"]?.toString().trim().replaceAll(
              RegExp(r'\s+'),
              '',
            ) ??
            "";
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
      setState(
        () => errorMessage = e.toString().replaceFirst("Exception: ", ""),
      );
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  String _nextDigerNumber() {
    // 10000'den itibaren boş olan ilk numarayı bul (10000, 10001, ...).
    // Eski/anormal yüksek numaralar yok sayılır; her zaman 10000'den gider.
    final used = <int>{};
    for (final s in students) {
      final level = s["school_level"]?.toString().trim().toLowerCase() ?? "";
      if (level != "diğer") continue;
      final num = int.tryParse(s["student_number"]?.toString() ?? "") ?? 0;
      if (num >= 10000) used.add(num);
    }
    int next = 10000;
    while (used.contains(next)) {
      next++;
    }
    return next.toString();
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
                    Text(
                      isDiger
                          ? "Öğrenci Numarası (Otomatik)"
                          : "Öğrenci Numarası",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: studentNumberController,
                      keyboardType: TextInputType.number,
                      enabled: !isDiger,
                      decoration: InputDecoration(
                        hintText: isDiger ? "" : "1001",
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Ad Soyad",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: fullNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: "Ali Yılmaz"),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Sınıf",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: classNameController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: "5A"),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Okul Seviyesi",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kTextPrimary,
                      ),
                    ),
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
                          })
                          .toList(),
                      onChanged: isAddingStudent
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                addStudentLevel = value;
                                if (value == "diğer") {
                                  studentNumberController.text =
                                      _nextDigerNumber();
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
                  onPressed: isAddingStudent
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text("Vazgeç"),
                ),
                ElevatedButton(
                  onPressed: isAddingStudent ? null : addManualStudent,
                  child: isAddingStudent
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
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
        SnackBar(
          content: Text(response["message"]?.toString() ?? "Öğrenci eklendi"),
        ),
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
      final startStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final endStr =
          "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

      await ApiService.createAnnouncement(
        schoolCode: widget.schoolCode,
        title: "Kitap İade Uyarısı",
        content:
            "Sayın $fullName, aldığınız kitabın iade tarihi geçmiştir. Lütfen kitabınızı kütüphaneye iade edin.",
        targetType: "section",
        // Numara + seviye: aynı numaralı başka seviyedeki öğrenci bu uyarıyı görmez.
        targetValues: [
          studentNumber,
          if ((student["school_level"]?.toString().trim() ?? "").isNotEmpty)
            "seviye:${student["school_level"].toString().trim().toLowerCase()}",
        ],
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
          content: Text(
            "Hata: ${e.toString().replaceFirst('Exception: ', '')}",
          ),
          backgroundColor: kDestructive,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingWarning = false);
    }
  }

  Widget buildStudentCard(Map<String, dynamic> student) {
    final studentNumber =
        student["student_number"]?.toString().trim().replaceAll(
          RegExp(r'\s+'),
          '',
        ) ??
        "";
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
                          color: isOverdue
                              ? kDestructive
                              : isLoaned
                              ? kWarning
                              : kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "No: ${student["student_number"] ?? "-"} · Sınıf: ${student["class_name"] ?? "-"} · ${student["school_level"] ?? "-"}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: kTextSecondary,
                        ),
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
                        onPressed: _sendingWarning
                            ? null
                            : () => _sendOverdueWarning(student),
                        icon: _sendingWarning
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.notifications_active, size: 14),
                        label: const Text(
                          "Uyar",
                          style: TextStyle(fontSize: 11),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDestructive,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                const Icon(
                  Icons.chevron_right,
                  color: kTextSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
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
  }

  Widget _summary(
    String title,
    String subtitle,
    int count,
    IconData icon,
    Color color,
    String tab,
  ) {
    final selected = selectedTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          selectedTab = tab;
          page = 0;
        }),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : Colors.white,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .17),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classes =
        students
            .map((s) => s['class_name']?.toString().trim().toUpperCase() ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort(compareClassNames);
    final query = ApiService.normalizeTurkishText(searchText);
    final visible = students.where((s) {
      final number = s['student_number']?.toString() ?? '';
      final level = s['school_level']?.toString().toLowerCase() ?? '';
      final key = '${number.trim().replaceAll(RegExp(r'\s+'), '')}_$level';
      final tabMatch =
          selectedTab == 'students' ||
          (selectedTab == 'loaned'
              ? loanedStudents.containsKey(key)
              : overdueStudents.contains(key));
      final classMatch =
          selectedClass == 'tümü' ||
          s['class_name']?.toString().trim().toUpperCase() == selectedClass;
      return tabMatch &&
          classMatch &&
          (query.isEmpty ||
              ApiService.normalizeTurkishText(
                s['full_name']?.toString() ?? '',
              ).contains(query) ||
              number.contains(query));
    }).toList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final student in visible) {
      final name =
          student['class_name']?.toString().trim().toUpperCase() ?? 'Diğer';
      grouped.putIfAbsent(name.isEmpty ? 'Diğer' : name, () => []).add(student);
    }
    final keys = grouped.keys.toList()..sort(compareClassNames);
    return Scaffold(
      backgroundColor: const Color(0xFFEAF5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEAF5FF),
        centerTitle: false,
        title: const Text(
          "Öğrenci Listesi",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF07164A),
          ),
        ),
        actions: [
          IconButton(
            onPressed: isLoading || isAddingStudent
                ? null
                : showAddStudentDialog,
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(child: Text(errorMessage))
          : RefreshIndicator(
              onRefresh: () async {
                await loadStudents();
                await loadLoanedStudents();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                children: [
                  Row(
                    children: [
                      _summary(
                        'Öğrenciler',
                        'Tüm öğrenciler',
                        students.length,
                        Icons.people,
                        const Color(0xFF1474D5),
                        'students',
                      ),
                      const SizedBox(width: 6),
                      _summary(
                        'Ödünçte',
                        'Kitap ödünçte olanlar',
                        loanedStudents.length,
                        Icons.menu_book,
                        const Color(0xFFF4A000),
                        'loaned',
                      ),
                      const SizedBox(width: 6),
                      _summary(
                        'Uyarılar',
                        'İade tarihi geçenler',
                        overdueStudents.length,
                        Icons.notifications_active,
                        const Color(0xFFE53935),
                        'warnings',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Okul Seviyesi'),
                            DropdownButtonFormField<String>(
                              key: ValueKey('level-$selectedLevel'),
                              initialValue: selectedLevel,
                              isExpanded: true,
                              items: schoolLevels
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e['value'],
                                      child: Text(e['label']!),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    selectedLevel = v;
                                    selectedClass = 'tümü';
                                  });
                                  loadStudents();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sınıf'),
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                'class-$selectedLevel-$selectedClass',
                              ),
                              initialValue: classes.contains(selectedClass)
                                  ? selectedClass
                                  : 'tümü',
                              isExpanded: true,
                              items: ['tümü', ...classes]
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e == 'tümü' ? 'Tümü' : e),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                selectedClass = v ?? 'tümü';
                                page = 0;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() {
                      searchText = v;
                      page = 0;
                    }),
                    decoration: InputDecoration(
                      hintText: 'Öğrenci adı veya numarası ara...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (keys.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('Öğrenci bulunamadı'),
                      ),
                    ),
                  for (final className in keys)
                    _classSection(className, grouped[className]!, keys.first),
                ],
              ),
            ),
    );
  }

  Widget _classSection(
    String className,
    List<Map<String, dynamic>> group,
    String firstClass,
  ) {
    final expanded =
        openClass == className ||
        (openClass == null && className == firstClass);
    final sorted = [...group]
      ..sort(
        (a, b) => (int.tryParse('${a['student_number']}') ?? 999999).compareTo(
          int.tryParse('${b['student_number']}') ?? 999999,
        ),
      );
    final start = page * pageSize;
    final slice = sorted.skip(start).take(pageSize).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.people, color: Color(0xFF1672D0)),
            title: Text(
              '$className Sınıfı',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF07164A),
              ),
            ),
            subtitle: Text('${group.length} öğrenci'),
            trailing: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            onTap: () => setState(() {
              openClass = expanded ? '' : className;
              page = 0;
            }),
          ),
          if (expanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  SizedBox(width: 46, child: Text('No')),
                  Expanded(child: Text('Öğrenci Adı')),
                  Text('Durum'),
                ],
              ),
            ),
            for (final student in slice) _studentRow(student),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(
                    'Toplam ${group.length} öğrenci',
                    style: const TextStyle(fontSize: 11),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: page > 0 ? () => setState(() => page--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${page + 1} / ${(group.length / pageSize).ceil()}'),
                  IconButton(
                    onPressed: start + pageSize < group.length
                        ? () => setState(() => page++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _studentRow(Map<String, dynamic> student) {
    final number = student['student_number']?.toString() ?? '';
    final level =
        student['school_level']?.toString().trim().toLowerCase() ?? '';
    final key = '${number.trim().replaceAll(RegExp(r'\s+'), '')}_$level';
    final overdue = overdueStudents.contains(key);
    final loaned = loanedStudents.containsKey(key);
    final name = student['full_name']?.toString() ?? '-';
    final initials = name
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0])
        .join();
    return InkWell(
      onTap: () => _openStudent(student),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEDF2FA))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(number, style: const TextStyle(fontSize: 12)),
            ),
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFDDEEFF),
              child: Text(initials, style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${student['school_level'] ?? ''} · ${student['class_name'] ?? ''}',
                    style: const TextStyle(fontSize: 10, color: kTextSecondary),
                  ),
                ],
              ),
            ),
            if (overdue)
              TextButton(
                onPressed: _sendingWarning
                    ? null
                    : () => _sendOverdueWarning(student),
                child: const Text(
                  'Uyarı Gönder',
                  style: TextStyle(color: kDestructive, fontSize: 10),
                ),
              )
            else if (loaned)
              const Text(
                'Ödünçte',
                style: TextStyle(color: kWarning, fontSize: 10),
              ),
            const Icon(Icons.chevron_right, size: 17),
          ],
        ),
      ),
    );
  }
}
