import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/student_auth_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../main.dart';
import '../services/full_screen_image_page.dart';
import 'student_books_screen.dart';
import 'student_reservations_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenBooks;
  const StudentHomeScreen({super.key, this.onOpenHistory, this.onOpenBooks});
  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  List<dynamic> _reservations = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = true;
  final Map<int, List<String>> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<StudentAuthProvider>();
      final results = await Future.wait([
        ApiService.getStudentReservations(),
        ApiService.getAnnouncements(schoolCode: auth.schoolCode ?? ''),
      ]);

      final res = results[0] as Map<String, dynamic>;
      if (res['success'] == true) {
        _reservations = res['data'] ?? [];
      }

      final allAnnouncements = results[1] as List<Map<String, dynamic>>;

      final now = DateTime.now();
      _announcements = allAnnouncements.where((a) {
        return _isAnnouncementVisibleToUser(a, auth, now);
      }).toList();

      // Yeni duyurular için bildirim göster — sadece kullanıcıya uygun olanlar
      await _checkAndNotifyNewAnnouncements(_announcements);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _checkAndNotifyNewAnnouncements(
    List<Map<String, dynamic>> all,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled =
          prefs.getBool('student_announcements_enabled') ?? true;
      final lastSeenId = prefs.getInt('last_seen_announcement_id') ?? 0;

      // En büyük ID'yi bul
      int maxId = lastSeenId;
      final newOnes = <Map<String, dynamic>>[];

      for (final a in all) {
        final id = a['id'] as int? ?? 0;
        if (id > lastSeenId) {
          newOnes.add(a);
        }
        if (id > maxId) maxId = id;
      }

      // Yeni duyurular için bildirim göster
      for (final a
          in notificationsEnabled ? newOnes : <Map<String, dynamic>>[]) {
        final id = a['id'] as int? ?? 0;
        final title = a['title']?.toString() ?? 'Yeni Duyuru';
        final content = a['content']?.toString() ?? '';
        final imageCount = a['image_count'] ?? 0;
        String? firstImage;
        if (imageCount > 0) {
          final imgs = await _fetchAnnouncementImages(id);
          firstImage = imgs.isNotEmpty ? imgs.first : null;
        }

        await NotificationService.showAnnouncementNotification(
          id: id,
          title: title,
          body: content,
          imageBase64: firstImage,
        );
      }

      if (maxId > lastSeenId) {
        await prefs.setInt('last_seen_announcement_id', maxId);
      }
    } catch (_) {}
  }

  bool _isAnnouncementVisibleToUser(
    Map<String, dynamic> a,
    StudentAuthProvider auth,
    DateTime now,
  ) {
    try {
      final start = DateTime.parse(a['start_date'] ?? '');
      final end = DateTime.parse(a['end_date'] ?? '');
      if (now.isBefore(start) || now.isAfter(end)) return false;
    } catch (_) {
      return false;
    }

    final targetType = a['target_type']?.toString() ?? 'all';
    if (targetType == 'all') return true;

    // target_values JSONB'den List veya String olarak gelebilir
    List<String> targetValues = [];
    final raw = a['target_values'];
    if (raw is List) {
      targetValues = raw
          .map((v) => v.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList();
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          targetValues = parsed
              .map((v) => v.toString().trim())
              .where((v) => v.isNotEmpty)
              .toList();
        }
      } catch (_) {
        targetValues = raw
            .split(',')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList();
      }
    }

    if (targetValues.isEmpty) return true;

    final userLevel = (auth.schoolLevel ?? '').toLowerCase().trim();
    // API login yanıtında sınıf bilgisi "user_class" olarak dönüyor
    final userClass =
        (auth.user?['user_class'] ?? auth.user?['class_name'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
    // Kişisel bildirimler (iade uyarısı vb.) student_number ile eşleşir
    final userStudentNumber = (auth.user?['student_number'] ?? '')
        .toString()
        .trim();

    if (targetType == 'school_level') {
      final targets = targetValues.map((v) => v.toLowerCase().trim()).toList();
      return targets.contains(userLevel);
    } else if (targetType == 'class') {
      final targets = targetValues.map((v) => v.toUpperCase().trim()).toList();
      return targets.contains(userClass);
    } else if (targetType == 'section') {
      // section tipi: overdue-notifier kişisel iade uyarıları için student_number kullanıyor
      // Uyarıda "seviye:<okul seviyesi>" etiketi varsa o da eşleşmeli; aynı
      // numaralı başka seviyedeki öğrencinin uyarısı gösterilmez.
      final levels = targetValues
          .where((v) => v.toLowerCase().startsWith('seviye:'))
          .map((v) => v.substring(7).toLowerCase().trim())
          .toList();
      return targetValues.contains(userStudentNumber) &&
          (levels.isEmpty || levels.contains(userLevel));
    }

    return false;
  }

  int get _totalReturned =>
      _reservations.where((r) => r['status'] == 'returned').length;

  Map<String, dynamic>? get _activeReservation {
    final active = _reservations.where((r) => r['status'] == 'loaned').toList();
    return active.isNotEmpty ? active.first : null;
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
    final auth = context.watch<StudentAuthProvider>();
    final name = auth.user?['user_name'] ?? 'Öğrenci';

    return Scaffold(
      backgroundColor: const Color(0xFFEAF5FF),
      body: RefreshIndicator(
        color: kPrimary,
        backgroundColor: kSurface,
        onRefresh: _fetch,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(name),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: kPrimary),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              _statsRow(),
              const SizedBox(height: 20),
              if (_activeReservation != null) _activeBookCard(),
              const SizedBox(height: 20),
              _quickActions(),
              if (_announcements.isNotEmpty) ...[
                const SizedBox(height: 24),
                _announcementsSection(),
              ],
              const SizedBox(height: 28),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(String name) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 24,
        bottom: 20,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(color: const Color(0xFFEAF5FF)),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C63C9), Color(0xFF082D81)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Icon(Icons.school_rounded, size: 31, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Merhaba, $name',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF07164A),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Kütüphane Panelin',
                  style: TextStyle(fontSize: 14, color: kTextSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              final item = _announcements.isNotEmpty
                  ? _announcements.first
                  : null;
              if (item != null) _showAllAnnouncements();
            },
            icon: Badge(
              isLabelVisible: _announcements.isNotEmpty,
              child: const Icon(
                Icons.notifications_rounded,
                color: Color(0xFF2156A5),
                size: 27,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAnnouncement(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item['title']?.toString() ?? 'Bilgilendirme'),
        content: Text(item['content']?.toString() ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showAllAnnouncements() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Bilgilendirmeler',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _announcements.length,
                  itemBuilder: (context, index) {
                    final item = _announcements[index];
                    return ListTile(
                      title: Text(item['title']?.toString() ?? ''),
                      subtitle: Text(
                        item['content']?.toString() ?? '',
                        maxLines: 2,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showAnnouncement(item);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsRow() {
    final active = _activeReservation;
    final days = active != null
        ? _daysRemaining(active['due_date']?.toString())
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              'Okunan Kitap',
              '$_totalReturned',
              Icons.menu_book_rounded,
              const Color(0xFF0A9C66),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              'Kalan Gün',
              active != null ? '$days' : '-',
              Icons.timer_outlined,
              days < 0 ? kDestructive : (days <= 3 ? kWarning : kPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withValues(alpha: .11),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: kTextSecondary),
          ),
        ],
      ),
    );
  }

  Widget _activeBookCard() {
    final r = _activeReservation!;
    final bookName = r['book_name'] ?? 'Bilinmeyen Kitap';
    final writer = r['book_writer'] ?? '';
    final days = _daysRemaining(r['due_date']?.toString());
    final dueDate = r['due_date']?.toString().split('T').first ?? '-';
    final coverUrl = r['cover_url']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_stories_rounded,
                  color: kPrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'AKTİF KİTABIN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: days < 0
                        ? kDestructive.withValues(alpha: 0.1)
                        : days <= 3
                        ? kWarning.withValues(alpha: 0.1)
                        : kSuccess.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    days < 0 ? '${days.abs()} gün gecikme' : '$days gün kaldı',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: days < 0
                          ? kDestructive
                          : (days <= 3 ? kWarning : kSuccess),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap:
                  widget.onOpenHistory ??
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentReservationsScreen(),
                    ),
                  ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF07164A),
                          ),
                        ),
                        if (writer.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: Color(0xFF5272A7),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  writer,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kTextSecondary),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 15,
                              color: Color(0xFF5272A7),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Teslim: $dueDate',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 103,
                      child: coverUrl.isEmpty
                          ? Container(
                              color: const Color(0xFFDDEEFF),
                              child: const Icon(
                                Icons.menu_book,
                                color: kPrimary,
                              ),
                            )
                          : Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFFDDEEFF),
                                child: const Icon(
                                  Icons.menu_book,
                                  color: kPrimary,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.chevron_right, color: kPrimary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    final auth = context.read<StudentAuthProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hızlı Erişim',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF07164A),
                  ),
                ),
              ),
              TextButton(
                onPressed:
                    widget.onOpenBooks ??
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentBooksScreen(
                          schoolCode: auth.schoolCode ?? '',
                        ),
                      ),
                    ),
                child: const Text('Tümünü Gör  ›'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionTile(
                  'Kitap Listesi',
                  'Okulundaki mevcut kitapları gör',
                  Icons.library_books_rounded,
                  kPrimary,
                  widget.onOpenBooks ??
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentBooksScreen(
                            schoolCode: auth.schoolCode ?? '',
                          ),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionTile(
                  'Rezervasyon Geçmişi',
                  'Tüm ödünç ve iade kayıtların',
                  Icons.history_rounded,
                  kTextSecondary,
                  widget.onOpenHistory ??
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentReservationsScreen(),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _announcementsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kWarning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: kWarning,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Bilgilendirmeler',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF07164A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kWarning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_announcements.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kWarning,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  if (_announcements.isNotEmpty) {
                    _showAllAnnouncements();
                  }
                },
                child: const Text('Tümünü Gör  ›'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._announcements.map((a) => _announcementCard(a)),
        ],
      ),
    );
  }

  Future<List<String>> _fetchAnnouncementImages(int id) async {
    if (_imageCache.containsKey(id)) return _imageCache[id]!;
    try {
      final images = await ApiService.getAnnouncementImages(id: id);
      _imageCache[id] = images;
      return images;
    } catch (_) {
      return [];
    }
  }

  Widget _announcementCard(Map<String, dynamic> a) {
    final title = a['title']?.toString() ?? '';
    final content = a['content']?.toString() ?? '';
    final senderName = a['sender_name']?.toString() ?? '';
    final endDate = a['end_date']?.toString().split('T').first ?? '';
    final isWarning = title.contains('Uyarı') || title.contains('uyarı');
    final accentColor = isWarning ? kDestructive : kSuccess;
    final imageCount = a['image_count'] ?? 0;
    final announcementId = a['id'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isWarning ? kDestructive.withValues(alpha: 0.03) : kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWarning ? kDestructive.withValues(alpha: 0.3) : kBorder,
          width: isWarning ? 1 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isWarning) ...[
                Icon(Icons.warning_rounded, size: 18, color: kDestructive),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isWarning ? kDestructive : kTextPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isWarning ? 'Uyarı' : 'Yeni',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (imageCount > 0)
            FutureBuilder<List<String>>(
              future: _fetchAnnouncementImages(announcementId),
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildAnnouncementImageGallery(snap.data!, title),
                );
              },
            ),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: isWarning
                  ? kDestructive.withValues(alpha: 0.8)
                  : kTextSecondary,
              height: 1.4,
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 13,
                color: kTextSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  senderName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.calendar_today_rounded,
                size: 12,
                color: kTextSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                endDate,
                style: const TextStyle(fontSize: 11, color: kTextSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementImageGallery(List<String> images, String title) {
    if (images.length == 1) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  FullScreenImagePage(imageList: images, title: title),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildAnnouncementImage(images.first),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImagePage(
                    imageList: images,
                    title: title,
                    initialIndex: i,
                  ),
                ),
              );
            },
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 160,
                    height: 140,
                    child: _buildAnnouncementImage(images[i]),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}/${images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnnouncementImage(String imageUrl) {
    // Base64 data URL ise decode et
    if (imageUrl.startsWith('data:')) {
      try {
        final parts = imageUrl.split(',');
        if (parts.length == 2) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(
            Uint8List.fromList(bytes),
            height: 140,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    // Normal HTTP URL ise network image kullan
    return Image.network(
      imageUrl,
      height: 140,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  Widget _actionTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: const Color(0xFFF7FBFF),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white, width: 1.3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(icon, color: color, size: 20)),
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF07164A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: kTextSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
