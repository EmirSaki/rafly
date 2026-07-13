import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';

class ReservationListPage extends StatefulWidget {
  final String schoolCode;

  const ReservationListPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<ReservationListPage> createState() => _ReservationListPageState();
}

class _ReservationListPageState extends State<ReservationListPage> {
  final TextEditingController searchController = TextEditingController();

  bool isLoading = true;
  String errorMessage = "";

  String selectedStatus = "tümü";
  String selectedClass = "tümü";
  List<String> classList = [];
  DateTime? filterStartDate;
  DateTime? filterEndDate;

  List<Map<String, dynamic>> reservations = [];

  final List<Map<String, String>> reservationStatuses = const [
    {"value": "tümü", "label": "Tümü"},
    {"value": "loaned", "label": "Ödünçte"},
    {"value": "returned", "label": "İade Edildi"},
  ];

  @override
  void initState() {
    super.initState();
    loadReservations();
    loadClasses();
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadClasses() async {
    try {
      final classes = await ApiService.getClasses(schoolCode: widget.schoolCode);
      if (!mounted) return;
      setState(() => classList = classes);
    } catch (_) {}
  }

  Future<void> loadReservations() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = "";
      });

      final result = await ApiService.getReservations(
        schoolCode: widget.schoolCode,
        startDate: filterStartDate == null ? null : formatDateForApi(filterStartDate!),
        endDate: filterEndDate == null ? null : formatDateForApi(filterEndDate!),
      );
      if (!mounted) return;
      setState(() => reservations = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String normalize(String value) => ApiService.normalizeTurkishText(value);

  List<Map<String, dynamic>> get filteredReservations {
    final searchText = normalize(searchController.text);

    return reservations.where((item) {
      final status = item["status"]?.toString().trim().toLowerCase() ?? "";
      final bookName = normalize(item["book_name"]?.toString() ?? "");
      final className = item["class_name"]?.toString().trim().toUpperCase() ?? "";

      final matchesStatus = selectedStatus == "tümü" || status == selectedStatus.toLowerCase();
      final matchesClass = selectedClass == "tümü" || className == selectedClass;
      final matchesBookName = searchText.isEmpty || bookName.contains(searchText);

      return matchesStatus && matchesClass && matchesBookName;
    }).toList();
  }

  String formatDateForApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> pickFilterDate({required bool isStart}) async {
    final initial = (isStart ? filterStartDate : filterEndDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        filterStartDate = picked;
        if (filterEndDate != null && filterEndDate!.isBefore(filterStartDate!)) {
          filterEndDate = filterStartDate;
        }
      } else {
        filterEndDate = picked;
        if (filterStartDate != null && filterStartDate!.isAfter(filterEndDate!)) {
          filterStartDate = filterEndDate;
        }
      }
    });
    await loadReservations();
  }

  Future<void> clearFilterDates() async {
    if (filterStartDate == null && filterEndDate == null) return;
    setState(() {
      filterStartDate = null;
      filterEndDate = null;
    });
    await loadReservations();
  }

  String formatDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty || raw == "null") return "-";
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return "${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}";
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

  int daysRemaining(dynamic dueDateValue) {
    final raw = dueDateValue?.toString();
    if (raw == null || raw.trim().isEmpty || raw == "null") return 0;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 0;
    final now = DateTime.now();
    return parsed.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  Future<void> returnBook(Map<String, dynamic> item) async {
    final id = int.tryParse(item["reservation_id"].toString());
    if (id == null) return;

    final bookName = item["book_name"]?.toString() ?? "Kitap";
    final studentName = item["student_name"]?.toString() ?? "-";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("İade Onayı"),
        content: Text("$bookName kitabını\n$studentName'den iade al?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hayır")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("İade Al")),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      setState(() => isLoading = true);
      final result = await ApiService.returnReservation(
        schoolCode: widget.schoolCode,
        reservationId: id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result["message"] ?? "İade edildi")),
      );
      await loadReservations();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: ${e.toString().replaceFirst("Exception: ", "")}")),
      );
      setState(() => isLoading = false);
    }
  }

  Widget buildReservationCard(Map<String, dynamic> item) {
    final status = item["status"]?.toString() ?? "";
    final isLoaned = status.toLowerCase() == "loaned";
    final days = daysRemaining(item["due_date"]);
    final isOverdue = isLoaned && days < 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOverdue ? kDestructive.withValues(alpha: 0.3) : kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item["book_name"]?.toString() ?? "Kitap",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          Text("ISBN: ${item["isbn"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          const Divider(height: 14),
          Text("Öğrenci: ${item["student_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Numara: ${item["student_number"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Sınıf: ${item["class_name"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          Text("Seviye: ${item["school_level"] ?? "-"}", style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                "İade tarihi: ${formatDate(item["due_date"])}",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextPrimary),
              ),
              if (isLoaned) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? kDestructive.withValues(alpha: 0.08)
                        : days <= 3
                            ? kWarning.withValues(alpha: 0.08)
                            : kSuccess.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isOverdue ? "${days.abs()} gün gecikmiş" : "$days gün kaldı",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isOverdue ? kDestructive : (days <= 3 ? kWarning : kSuccess),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (isLoaned) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : () => returnBook(item),
                  icon: const Icon(Icons.assignment_return, size: 16),
                  label: const Text("İade Al"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Durum", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: selectedStatus,
            items: reservationStatuses.map((s) {
              return DropdownMenuItem<String>(value: s["value"], child: Text(s["label"]!));
            }).toList(),
            onChanged: isLoading ? null : (value) {
              if (value == null) return;
              setState(() => selectedStatus = value);
            },
          ),
          const SizedBox(height: 10),
          const Text("Sınıf", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: classList.contains(selectedClass) || selectedClass == "tümü" ? selectedClass : "tümü",
            items: [
              const DropdownMenuItem<String>(value: "tümü", child: Text("Tümü")),
              ...classList.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))),
            ],
            onChanged: isLoading ? null : (value) {
              if (value == null) return;
              setState(() => selectedClass = value);
            },
          ),
          const SizedBox(height: 10),
          const Text("Tarih Aralığı", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : () => pickFilterDate(isStart: true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(filterStartDate == null ? "Başlangıç" : formatDate(formatDateForApi(filterStartDate!))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : () => pickFilterDate(isStart: false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(filterEndDate == null ? "Bitiş" : formatDate(formatDateForApi(filterEndDate!))),
                ),
              ),
              if (filterStartDate != null || filterEndDate != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: isLoading ? null : clearFilterDates,
                  icon: const Icon(Icons.clear, color: kTextSecondary),
                  tooltip: "Tarihi temizle",
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: "Kitap adına göre ara",
              prefixIcon: const Icon(Icons.search, color: kTextSecondary),
              suffixIcon: searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, color: kTextSecondary),
                      onPressed: () => searchController.clear(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleReservations = filteredReservations;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Rezervasyon Listesi"),
        actions: [
          IconButton(
            onPressed: isLoading ? null : loadReservations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: kBackground,
      body: Column(
        children: [
          buildFilters(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: kDestructive, fontWeight: FontWeight.w500)),
                        ),
                      )
                    : visibleReservations.isEmpty
                        ? const Center(
                            child: Text("Rezervasyon bulunamadı",
                                style: TextStyle(fontSize: 14, color: kTextSecondary)),
                          )
                        : RefreshIndicator(
                            onRefresh: loadReservations,
                            child: ListView.builder(
                              padding: EdgeInsets.only(
                                top: 6,
                                bottom: MediaQuery.of(context).padding.bottom + 20,
                              ),
                              itemCount: visibleReservations.length,
                              itemBuilder: (context, index) {
                                return buildReservationCard(visibleReservations[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
