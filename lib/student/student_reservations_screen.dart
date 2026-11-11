import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StudentReservationsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const StudentReservationsScreen({super.key, this.onBack});

  @override
  State<StudentReservationsScreen> createState() =>
      _StudentReservationsScreenState();
}

class _StudentReservationsScreenState extends State<StudentReservationsScreen> {
  List<Map<String, dynamic>> _reservations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiService.getStudentReservations();
      if (!mounted) return;
      if (response['success'] == true) {
        setState(
          () => _reservations = (response['data'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList(),
        );
      } else {
        setState(() => _error = 'Rezervasyonlar yüklenemedi');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '-';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int? _daysRemaining(dynamic value) {
    final due = DateTime.tryParse(value?.toString() ?? '');
    if (due == null) return null;
    final today = DateTime.now();
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8FF),
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _HistoryWaves())),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      _roundButton(Icons.arrow_back_ios_new_rounded, _back),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Rezervasyon Geçmişi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF07164A),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _roundButton(Icons.history_rounded, _fetch),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Text(_error!, textAlign: TextAlign.center),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          child: _reservations.isEmpty
                              ? ListView(
                                  children: const [
                                    SizedBox(height: 120),
                                    Center(
                                      child: Text('Henüz rezervasyon yok'),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    30,
                                  ),
                                  itemCount: _reservations.length,
                                  itemBuilder: (_, index) =>
                                      _card(_reservations[index]),
                                ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback action) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 4,
    shadowColor: const Color(0xFFB9CDE7),
    child: IconButton(
      onPressed: action,
      icon: Icon(icon, color: const Color(0xFF1461D4)),
      iconSize: 23,
      padding: const EdgeInsets.all(13),
    ),
  );

  Widget _card(Map<String, dynamic> reservation) {
    final title = reservation['book_name']?.toString() ?? 'Bilinmeyen Kitap';
    final writer = reservation['book_writer']?.toString() ?? '';
    final cover = reservation['cover_url']?.toString() ?? '';
    final status =
        (reservation['status'] ?? reservation['reservation_status'])
            ?.toString() ??
        '';
    final loaned = status == 'loaned';
    final remaining = loaned ? _daysRemaining(reservation['due_date']) : null;
    final statusColor = loaned
        ? const Color(0xFF1551AE)
        : const Color(0xFF138C67);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x207FA7D4),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              width: 84,
              height: 128,
              child: cover.isEmpty
                  ? _coverFallback()
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _coverFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF07164A),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      loaned
                          ? Icons.menu_book_rounded
                          : Icons.check_circle_rounded,
                      color: statusColor,
                      size: 19,
                    ),
                  ],
                ),
                if (writer.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    writer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF61749C),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    loaned ? 'Ödünç Verildi' : 'İade Edildi',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _dateLine('Alınma Tarihi', _date(reservation['reserved_at'])),
                const SizedBox(height: 5),
                _dateLine(
                  loaned ? 'Teslim Tarihi' : 'İade Tarihi',
                  _date(
                    loaned
                        ? reservation['due_date']
                        : reservation['returned_at'],
                  ),
                ),
                if (remaining != null) ...[
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: remaining < 0
                          ? const Color(0xFFFFE8EB)
                          : const Color(0xFFE5F5ED),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      remaining < 0
                          ? '${remaining.abs()} gün gecikme!'
                          : '$remaining gün kaldı',
                      style: TextStyle(
                        color: remaining < 0
                            ? const Color(0xFFCF1025)
                            : const Color(0xFF148448),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverFallback() => Container(
    color: const Color(0xFFDCEBFC),
    child: const Icon(
      Icons.menu_book_rounded,
      color: Color(0xFF1461D4),
      size: 38,
    ),
  );

  Widget _dateLine(String label, String value) => Row(
    children: [
      const Icon(
        Icons.calendar_month_outlined,
        size: 14,
        color: Color(0xFF275BA9),
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          '$label: $value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFF405680)),
        ),
      ),
    ],
  );
}

class _HistoryWaves extends CustomPainter {
  const _HistoryWaves();

  @override
  void paint(Canvas canvas, Size size) {
    final top = Paint()..color = const Color(0xFFE2F0FF);
    canvas.drawCircle(
      Offset(size.width * .22, -size.width * .7),
      size.width * .95,
      top,
    );
    final colors = [
      const Color(0xFFD5EAFF),
      const Color(0xFFABD3FB),
      const Color(0xFF78B8F4),
    ];
    for (var i = 0; i < colors.length; i++) {
      final y = size.height - 105 + i * 27;
      final path = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * .25, y - 45, size.width * .52, y + 20)
        ..quadraticBezierTo(size.width * .78, y + 48, size.width, y - 3)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
