import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'reservation_pagination.dart';

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
  int pageIndex = 0;

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
    searchController.addListener(() => setState(() => pageIndex = 0));
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
      pageIndex = 0;
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
      pageIndex = 0;
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

  Widget _compactReservationCard(Map<String, dynamic> item) {
    final isLoaned = item['status']?.toString().toLowerCase() == 'loaned';
    final days = daysRemaining(item['due_date']);
    final coverUrl = item['cover_url']?.toString() ?? '';
    final title = item['book_name']?.toString() ?? 'Kitap';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .93),
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [BoxShadow(color: Color(0x1C5B9AD8), blurRadius: 11, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(7), child: coverUrl.isEmpty
            ? Container(width: 43, height: 66, color: const Color(0xFFE3EFFF),
                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF76A6DC)))
            : Image.network(coverUrl, width: 43, height: 66, fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Container(width: 43, height: 66,
                  color: const Color(0xFFE3EFFF), child: const Icon(Icons.menu_book_rounded)))),
          const SizedBox(width: 7),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w700,
                color: Color(0xFF071E52))),
            const SizedBox(height: 4),
            Text('ISBN: ${item['isbn'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: Color(0xFF5D708E))),
            const SizedBox(height: 4),
            _cardInfo(Icons.person_outline_rounded, item['student_name']?.toString() ?? '-'),
            _cardInfo(Icons.class_outlined,
              '${item['class_name'] ?? '-'}  |  No: ${item['student_number'] ?? '-'}'),
            _cardInfo(Icons.calendar_month_outlined,
              isLoaned ? formatDate(item['due_date']) : 'İade: ${formatDate(item['returned_at'])}'),
          ])),
        ]),
        if (isLoaned) ...[
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: Text(
            days < 0 ? '${days.abs()} gün gecikmiş' : '$days gün kaldı',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: days < 0 ? kDestructive : kSuccess))),
          const SizedBox(height: 4),
          SizedBox(height: 32, child: ElevatedButton.icon(
            onPressed: isLoading ? null : () => returnBook(item),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF123E82),
              foregroundColor: Colors.white, padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
            icon: const Icon(Icons.assignment_return_rounded, size: 13),
            label: const Text('İade Al', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)))),
        ] else ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE5F8ED), borderRadius: BorderRadius.circular(8)),
            child: const Text('İade edildi', style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w700, color: Color(0xFF179456))))),
        ],
      ]),
    );
  }

  Widget _cardInfo(IconData icon, String value) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(children: [Icon(icon, size: 11, color: const Color(0xFF173F83)),
      const SizedBox(width: 3), Expanded(child: Text(value, maxLines: 1,
        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Color(0xFF4D6387))))]));

  Widget _designedFilters() {
    InputDecoration fieldDecoration() => InputDecoration(
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDCE7F5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF8FC2F2))));
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Column(children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Durum', style: TextStyle(fontSize: 11, color: Color(0xFF14254B))),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(initialValue: selectedStatus, decoration: fieldDecoration(),
            items: reservationStatuses.map((s) => DropdownMenuItem<String>(
              value: s['value'], child: Text(s['label']!, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: isLoading ? null : (value) { if (value != null) setState(() { selectedStatus = value; pageIndex = 0; }); }),
        ])),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sınıf', style: TextStyle(fontSize: 11, color: Color(0xFF14254B))),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: classList.contains(selectedClass) || selectedClass == 'tümü' ? selectedClass : 'tümü',
            decoration: fieldDecoration(),
            items: [const DropdownMenuItem(value: 'tümü', child: Text('Tümü', style: TextStyle(fontSize: 12))),
              ...classList.map((c) => DropdownMenuItem(value: c,
                child: Text(c, style: const TextStyle(fontSize: 12))))],
            onChanged: isLoading ? null : (value) { if (value != null) setState(() { selectedClass = value; pageIndex = 0; }); }),
        ])),
      ]),
      const SizedBox(height: 8),
      const Align(alignment: Alignment.centerLeft, child: Text('Tarih Aralığı',
        style: TextStyle(fontSize: 11, color: Color(0xFF14254B)))),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: _dateButton(isStart: true)),
        const SizedBox(width: 9),
        Expanded(child: _dateButton(isStart: false)),
        if (filterStartDate != null || filterEndDate != null)
          IconButton(onPressed: isLoading ? null : clearFilterDates,
            icon: const Icon(Icons.clear, size: 18), tooltip: 'Tarihi temizle'),
      ]),
      const SizedBox(height: 9),
      TextField(controller: searchController, textCapitalization: TextCapitalization.words,
        decoration: fieldDecoration().copyWith(hintText: 'Kitap adına göre ara...',
          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF8A99AF)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF50678D)),
          suffixIcon: searchController.text.trim().isEmpty ? null : IconButton(
            onPressed: searchController.clear, icon: const Icon(Icons.clear, size: 18)))),
    ]));
  }

  Widget _dateButton({required bool isStart}) => SizedBox(height: 40, child: OutlinedButton.icon(
    onPressed: isLoading ? null : () => pickFilterDate(isStart: isStart),
    style: OutlinedButton.styleFrom(backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFDCE7F5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 4)),
    icon: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF163D81)),
    label: Text((isStart ? filterStartDate : filterEndDate) == null
      ? (isStart ? 'Başlangıç' : 'Bitiş')
      : formatDate(formatDateForApi((isStart ? filterStartDate : filterEndDate)!)),
      style: const TextStyle(fontSize: 11, color: Color(0xFF14254B)))));

  @override
  Widget build(BuildContext context) {
    final visibleReservations = filteredReservations;
    final loaned = visibleReservations.where((r) =>
      r['status']?.toString().toLowerCase() == 'loaned').toList();
    final returned = visibleReservations.where((r) =>
      r['status']?.toString().toLowerCase() == 'returned').toList();
    final totalPages = reservationPageCount(loaned.length, returned.length);
    final currentPage = pageIndex.clamp(0, totalPages - 1);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: const Color(0xFFE8F5FF),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 66,
        leading: Padding(padding: const EdgeInsets.only(left: 10), child: Material(
          color: Colors.white, shape: const CircleBorder(), elevation: 3,
          child: IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF092A78))))),
        centerTitle: true,
        title: const Text('Rezervasyon Listesi', style: TextStyle(fontSize: 17,
          fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 10), child: Material(
            color: Colors.white, shape: const CircleBorder(), elevation: 3, child: IconButton(
            onPressed: isLoading ? null : loadReservations,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF176DE1)),
          ))),
        ],
      ),
      backgroundColor: const Color(0xFFE8F5FF),
      body: Container(decoration: const BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFE8F5FF), Color(0xFFF7FBFF)])), child: Column(
        children: [
          _designedFilters(),
          Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 5), child: Row(children: [
            Expanded(child: _summaryCard('Ödünçte', 'Şu anda ödünçte olan kitaplar',
              reservations.where((r) => r['status']?.toString().toLowerCase() == 'loaned').length,
              Icons.menu_book_rounded, true)),
            const SizedBox(width: 9),
            Expanded(child: _summaryCard('İade Edildi', 'İade edilen kitaplar',
              reservations.where((r) => r['status']?.toString().toLowerCase() == 'returned').length,
              Icons.check_circle_rounded, false)),
          ])),
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
                            child: LayoutBuilder(builder: (context, constraints) {
                              final cardWidth = (constraints.maxWidth - 25) / 2;
                              Widget column(List<Map<String, dynamic>> items) => SizedBox(
                                width: cardWidth,
                                child: Column(children: [for (final item in items) ...[
                                  _compactReservationCard(item), const SizedBox(height: 9),
                                ]]));
                              return ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 30),
                                children: [Row(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [column(reservationPage(loaned, currentPage)),
                                    const SizedBox(width: 9),
                                    column(reservationPage(returned, currentPage))])]);
                            }),
                          ),
          ),
          if (!isLoading && errorMessage.isEmpty && visibleReservations.isNotEmpty)
            _pagination(currentPage, totalPages),
        ],
      )),
    );
  }

  Widget _summaryCard(String title, String subtitle, int count, IconData icon, bool dark) =>
    Container(height: 59, padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
        gradient: dark ? const LinearGradient(colors: [Color(0xFF207BEC), Color(0xFF064BAC)])
          : const LinearGradient(colors: [Color(0xFFD7ECFF), Color(0xFFC7E5FF)])),
      child: Row(children: [Icon(icon, size: 26, color: dark ? Colors.white : const Color(0xFF0D5FBE)),
        const SizedBox(width: 6), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700, color: dark ? Colors.white : const Color(0xFF0D3F82))),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8,
            color: dark ? Colors.white70 : const Color(0xFF5680AE))),
        ])),
        Text('$count', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
          color: dark ? Colors.white : const Color(0xFF0D4D9C)))]));

  Widget _pagination(int currentPage, int totalPages) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x1C5B9AD8), blurRadius: 11,
          offset: Offset(0, 4))]),
      child: Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: currentPage == 0 ? null : () => setState(() => pageIndex = currentPage - 1),
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('Önceki', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF123E82),
            side: const BorderSide(color: Color(0xFFD7E8FA)),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Sayfa ${currentPage + 1} / $totalPages',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: Color(0xFF071E52)))),
        Expanded(child: ElevatedButton(
          onPressed: currentPage + 1 >= totalPages ? null :
            () => setState(() => pageIndex = currentPage + 1),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B59C4),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Sonraki', style: TextStyle(fontSize: 11)),
            Icon(Icons.chevron_right_rounded, size: 18),
          ]))),
      ]),
    ),
  );
}
