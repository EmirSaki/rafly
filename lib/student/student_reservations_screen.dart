import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';

class StudentReservationsScreen extends StatefulWidget {
  const StudentReservationsScreen({super.key});
  @override
  State<StudentReservationsScreen> createState() => _StudentReservationsScreenState();
}

class _StudentReservationsScreenState extends State<StudentReservationsScreen> {
  List<dynamic> _reservations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getStudentReservations();
      if (res['success'] == true) {
        _reservations = res['data'] ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'loaned': return 'Ödünç Verildi';
      case 'returned': return 'İade Edildi';
      default: return status ?? '-';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'loaned': return kPrimary;
      case 'returned': return kSuccess;
      default: return kTextSecondary;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'loaned': return Icons.auto_stories_rounded;
      case 'returned': return Icons.check_circle_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  int _daysRemaining(String? dueDate) {
    if (dueDate == null) return 0;
    try {
      final due = DateTime.parse(dueDate);
      final now = DateTime.now();
      return due.difference(DateTime(now.year, now.month, now.day)).inDays;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('Rezervasyon Geçmişi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _reservations.isEmpty
              ? const Center(child: Text('Henüz rezervasyon yok', style: TextStyle(color: kTextSecondary)))
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _fetch,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    itemCount: _reservations.length,
                    itemBuilder: (_, i) => _reservationTile(_reservations[i]),
                  ),
                ),
    );
  }

  Widget _reservationTile(Map<String, dynamic> r) {
    final bookName = r['book_name'] ?? 'Bilinmeyen Kitap';
    final writer = r['book_writer'] ?? '';
    final status = r['status'] ?? r['reservation_status'];
    final color = _statusColor(status);
    final reservedAt = r['reserved_at']?.toString().split('T').first ?? '-';
    final dueDate = r['due_date']?.toString().split('T').first;
    final returnedAt = r['returned_at']?.toString().split('T').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(_statusIcon(status), color: color, size: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(bookName, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLabel(status),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          if (writer.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(writer, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: kTextSecondary),
              const SizedBox(width: 4),
              Text('Alınma: $reservedAt', style: const TextStyle(fontSize: 11, color: kTextSecondary)),
              if (dueDate != null) ...[
                const SizedBox(width: 14),
                const Icon(Icons.event_rounded, size: 12, color: kTextSecondary),
                const SizedBox(width: 4),
                Text('Teslim: $dueDate', style: const TextStyle(fontSize: 11, color: kTextSecondary)),
              ],
              if (returnedAt != null) ...[
                const SizedBox(width: 14),
                const Icon(Icons.assignment_turned_in_rounded, size: 12, color: kSuccess),
                const SizedBox(width: 4),
                Text('İade: $returnedAt', style: const TextStyle(fontSize: 11, color: kSuccess)),
              ],
            ],
          ),
          if (status == 'loaned' && dueDate != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final days = _daysRemaining(r['due_date']?.toString());
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: days < 0
                      ? kDestructive.withValues(alpha: 0.08)
                      : days <= 3
                          ? kWarning.withValues(alpha: 0.08)
                          : kSuccess.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  days < 0 ? '${days.abs()} gün gecikme!' : '$days gün kaldı',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: days < 0 ? kDestructive : (days <= 3 ? kWarning : kSuccess),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
