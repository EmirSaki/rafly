import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'add_book_page.dart';
import 'book_list_page.dart';
import 'create_announcement_page.dart';
import 'reservation_menu_page.dart';
import 'student_list_page.dart';

class HomePage extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String userName;
  final String userSurname;
  final String userRole;
  final String? schoolLogoUrl;

  const HomePage({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.userName,
    required this.userSurname,
    required this.userRole,
    this.schoolLogoUrl,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _logoUrl;
  bool _isUploadingLogo = false;

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.schoolLogoUrl;
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/905350127504?text=${Uri.encodeComponent('Merhaba, Rafly hakkında bilgi almak istiyorum.')}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp açılamadı')),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Oturumunuz sonlandırılacak. Devam etmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kDestructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_role');
      await prefs.remove('admin_school_code');
      await prefs.remove('admin_school_name');
      await prefs.remove('admin_user_name');
      await prefs.remove('admin_user_surname');
      await prefs.remove('admin_user_role');

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
        (route) => false,
      );
    }
  }

  bool get isTeacher =>
      widget.userRole.toLowerCase() == "teacher" ||
      widget.userRole.toLowerCase() == "admin";

  bool get isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<void> _pickAndUploadLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final fileName = picked.name;

    if (!mounted) return;

    setState(() => _isUploadingLogo = true);

    try {
      final result = await ApiService.uploadSchoolLogo(
        schoolCode: widget.schoolCode,
        imageBytes: bytes,
        fileName: fileName,
      );

      if (!mounted) return;

      final newLogoUrl = result["data"]?["logo_url"]?.toString();
      setState(() => _logoUrl = newLogoUrl);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Okul logosu güncellendi")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logo yüklenemedi: ${e.toString().replaceFirst('Exception: ', '')}")),
      );
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    setState(() => _isUploadingLogo = true);

    try {
      await ApiService.deleteSchoolLogo(schoolCode: widget.schoolCode);

      if (!mounted) return;

      setState(() => _logoUrl = null);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Okul logosu kaldırıldı")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logo silinemedi: ${e.toString().replaceFirst('Exception: ', '')}")),
      );
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  void _showLogoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    "Okul Logosu",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file, color: kPrimary),
                  title: const Text("Logo Yükle / Değiştir"),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadLogo();
                  },
                ),
                if (_logoUrl != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: kDestructive),
                    title: const Text("Logoyu Kaldır"),
                    onTap: () {
                      Navigator.pop(ctx);
                      _removeLogo();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogo() {
    if (_logoUrl != null && _logoUrl!.startsWith("data:")) {
      try {
        final base64Str = _logoUrl!.split(",").last;
        final bytes = base64Decode(base64Str);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(),
          ),
        );
      } catch (_) {
        return _buildDefaultLogo();
      }
    }

    return _buildDefaultLogo();
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.local_library_outlined,
        color: kPrimary,
        size: 22,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = '${widget.userName} ${widget.userSurname}'.trim();

    return Scaffold(
      backgroundColor: kBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openWhatsApp,
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.chat_rounded, size: 20),
        label: const Text(
          'Bize Ulaşın',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildLogo(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _logoUrl != null ? widget.schoolName : "Rafly",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: kPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isTeacher && isDesktop)
                    _isUploadingLogo
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            onPressed: _showLogoOptions,
                            icon: const Icon(Icons.camera_alt_outlined, size: 20),
                            tooltip: "Okul Logosu",
                            color: kTextSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                  IconButton(
                    onPressed: _confirmLogout,
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    tooltip: "Çıkış Yap",
                    color: kDestructive,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.schoolName.isNotEmpty ? widget.schoolName : "Hoşgeldiniz",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Okul Kodu: ${widget.schoolCode}",
                      style: const TextStyle(fontSize: 13, color: kTextSecondary),
                    ),
                    if (fullName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        "$fullName${widget.userRole.isNotEmpty ? ' - ${widget.userRole}' : ''}",
                        style: const TextStyle(fontSize: 13, color: kTextSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Hızlı Erişim",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.add_circle_outline,
                title: "Kitap Ekleme",
                subtitle: "Barkod veya manuel ekleme",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddBookPage(schoolCode: widget.schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMenuCard(
                context,
                icon: Icons.library_books_outlined,
                title: "Kitap Listesi",
                subtitle: "Envanterdeki kitapları görüntüle",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookListPage(schoolCode: widget.schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMenuCard(
                context,
                icon: Icons.assignment_outlined,
                title: "Rezervasyonlar",
                subtitle: "Kitap ver, iade al, geçmiş",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReservationMenuPage(schoolCode: widget.schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMenuCard(
                context,
                icon: Icons.people_outline,
                title: "Öğrenci Listesi",
                subtitle: "Öğrenci yönetimi",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentListPage(schoolCode: widget.schoolCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMenuCard(
                context,
                icon: Icons.campaign_outlined,
                title: "Bildirim Gönder",
                subtitle: "Duyuru ve bilgilendirme gönder",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateAnnouncementPage(schoolCode: widget.schoolCode),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: kTextSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
