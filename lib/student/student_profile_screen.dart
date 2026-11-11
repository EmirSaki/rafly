import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/student_auth_provider.dart';
import '../services/api_service.dart';
import '../main.dart';

class StudentProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const StudentProfileScreen({super.key, this.onBack});
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _editing = false;
  bool _contactExpanded = true;
  bool _passwordExpanded = false;
  int _activeEditTab = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final auth = context.read<StudentAuthProvider>();
    _emailCtrl.text = auth.user?['email'] ?? '';
    _phoneCtrl.text = auth.user?['phone'] ?? '';
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.updateStudentProfile(
        email: _emailCtrl.text.trim().isNotEmpty
            ? _emailCtrl.text.trim()
            : null,
        phone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        context.read<StudentAuthProvider>().markProfileCompleted(
          res['data'] ?? {},
        );
        _passwordCtrl.clear();
        setState(() {
          _editing = false;
          _passwordExpanded = false;
          _contactExpanded = true;
          _activeEditTab = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil güncellendi'),
            backgroundColor: kSuccess,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Hata oluştu'),
            backgroundColor: kDestructive,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bağlantı hatası'),
            backgroundColor: kDestructive,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _notificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var enabled = prefs.getBool('student_announcements_enabled') ?? true;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Bildirim Tercihleri',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  title: const Text('Duyuru bildirimleri'),
                  value: enabled,
                  onChanged: (value) async {
                    update(() => enabled = value);
                    await prefs.setBool('student_announcements_enabled', value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı')));
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hesabı Sil'),
        content: const Text(
          'Hesabın ve kişisel verilerin kalıcı olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Hesabı Sil',
              style: TextStyle(color: kDestructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final result = await ApiService.deleteStudentAccount();
      if (!mounted) return;
      if (result['success'] == true) {
        await context.read<StudentAuthProvider>().logout();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'Hesap silinemedi'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<StudentAuthProvider>();
    final user = auth.user;
    final name = '${user?['user_name'] ?? ''} ${user?['user_surname'] ?? ''}'
        .trim();
    final studentNumber = user?['student_number'] ?? user?['student_id'] ?? '-';
    final userClass = user?['user_class'] ?? '-';
    final schoolLevel = auth.schoolLevel ?? '-';
    final schoolLevelLabel = schoolLevel.isEmpty
        ? '-'
        : '${schoolLevel[0].toUpperCase()}${schoolLevel.substring(1)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F7FF),
        leading: IconButton(
          onPressed: widget.onBack ?? () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF07164A),
          ),
        ),
        title: const Text(
          'Profil',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF07164A),
          ),
        ),
        actions: [
          if (!_editing)
            TextButton.icon(
              icon: const Icon(
                Icons.edit_rounded,
                size: 18,
                color: Color(0xFF0848B7),
              ),
              label: const Text(
                'Profilini Düzenle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0848B7),
                ),
              ),
              onPressed: () => setState(() {
                _editing = true;
                _contactExpanded = true;
                _passwordExpanded = false;
                _activeEditTab = 0;
              }),
            )
          else
            TextButton.icon(
              icon: const Icon(
                Icons.edit_rounded,
                size: 18,
                color: Color(0xFF0848B7),
              ),
              label: const Text(
                'Profilini Düzenle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0848B7),
                ),
              ),
              onPressed: () {
                _loadProfile();
                _passwordCtrl.clear();
                setState(() {
                  _editing = false;
                  _passwordExpanded = false;
                  _contactExpanded = true;
                  _activeEditTab = 0;
                });
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2480A7D8),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1378ED), Color(0xFF082D81)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF07164A),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Öğrenci No: $studentNumber  |  Sınıf: $userClass',
                    style: const TextStyle(fontSize: 13, color: kTextSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _infoCard([
            _infoRow(
              Icons.apartment_rounded,
              'Okul Kodu',
              auth.schoolCode ?? '-',
            ),
            _infoRow(Icons.school_rounded, 'Okul Seviyesi', schoolLevelLabel),
            _infoRow(Icons.tag_rounded, 'Öğrenci No', studentNumber.toString()),
            _infoRow(Icons.people_alt_rounded, 'Sınıf', userClass.toString()),
          ]),
          const SizedBox(height: 16),

          if (!_editing)
            const Row(
              children: [
                Icon(Icons.phone, color: Color(0xFF1469DA), size: 19),
                SizedBox(width: 9),
                Text(
                  'İLETİŞİM BİLGİLERİ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF07164A),
                  ),
                ),
              ],
            ),
          if (!_editing) const SizedBox(height: 10),

          if (_editing) ...[
            _editingContactCard(),
            const SizedBox(height: 12),
            if (_activeEditTab != 2) ...[
              _editingPasswordCard(),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _save,
                icon: const Icon(Icons.save_rounded),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0753CD),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                label: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Kaydet'),
              ),
            ),
          ] else ...[
            _infoCard([
              _infoRow(
                Icons.mail_outline_rounded,
                'E-posta',
                _emailCtrl.text.isNotEmpty ? _emailCtrl.text : 'Eklenmemiş',
              ),
              _infoRow(
                Icons.phone_rounded,
                'Telefon',
                _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : 'Eklenmemiş',
              ),
            ]),
          ],

          SizedBox(height: _editing ? 12 : 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () async => await auth.logout(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Çıkış Yap'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kDestructive,
                side: const BorderSide(color: kDestructive, width: 1),
                backgroundColor: const Color(0xFFFFF0F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> children) => Material(
    color: const Color(0xFFF9FCFF),
    elevation: 3,
    shadowColor: const Color(0x4482A7D5),
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: children),
    ),
  );

  Widget _infoRow(IconData icon, String label, String value) => Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FBFF),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFE7F0FC)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFE2F0FF),
          child: Icon(icon, color: const Color(0xFF1269DB), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: kTextSecondary),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF07164A),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _editingContactCard() => _infoCard([
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.phone, color: Color(0xFF1269DB)),
      title: const Text(
        'İletişim Bilgileri',
        style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF07164A)),
      ),
      trailing: Icon(
        _contactExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        color: const Color(0xFF07164A),
      ),
      onTap: () => setState(() => _contactExpanded = !_contactExpanded),
    ),
    if (_contactExpanded) ...[
      Row(
        children: [
          Expanded(
            child: _editTab(
              Icons.phone,
              'İletişim Bilgileri',
              _activeEditTab == 0,
              () => setState(() {
                _contactExpanded = true;
                _passwordExpanded = false;
                _activeEditTab = 0;
              }),
            ),
          ),
          Expanded(
            child: _editTab(
              Icons.lock,
              'Şifre Yenile',
              _activeEditTab == 1,
              () => setState(() {
                _contactExpanded = true;
                _passwordExpanded = true;
                _activeEditTab = 1;
              }),
            ),
          ),
          Expanded(
            child: _editTab(
              Icons.more_horiz_rounded,
              'Diğer',
              _activeEditTab == 2,
              () => setState(() {
                _contactExpanded = true;
                _passwordExpanded = false;
                _activeEditTab = 2;
              }),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_activeEditTab == 0) ...[
        _editRow(
          Icons.mail_outline_rounded,
          'E-posta',
          _emailCtrl,
          'E-posta adresinizi girin',
          TextInputType.emailAddress,
        ),
        const SizedBox(height: 7),
        _editRow(
          Icons.phone_rounded,
          'Telefon',
          _phoneCtrl,
          'Telefon numaranızı girin',
          TextInputType.phone,
        ),
      ] else if (_activeEditTab == 2) ...[
        _otherRow(
          Icons.notifications_none_rounded,
          'Bildirim Tercihleri',
          _notificationPreferences,
        ),
        _otherRow(
          Icons.verified_user_outlined,
          'Gizlilik ve Güvenlik',
          () => _openExternal(Uri.https('raflylib.online', 'privacy.html')),
        ),
        _otherRow(
          Icons.help_outline_rounded,
          'Yardım ve Destek',
          () => _openExternal(
            Uri.parse(
              'https://wa.me/905350127504?text=${Uri.encodeComponent('Merhaba, Rafly için desteğe ihtiyacım var.')}',
            ),
          ),
        ),
        _otherRow(
          Icons.delete_outline_rounded,
          'Hesabı Sil',
          _deleteAccount,
          destructive: true,
        ),
      ],
    ],
  ]);

  Widget _editingPasswordCard() => _infoCard([
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_rounded, color: Color(0xFF1269DB)),
      title: const Text(
        'Şifre Yenile',
        style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF07164A)),
      ),
      trailing: Icon(
        _passwordExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        color: const Color(0xFF07164A),
      ),
      onTap: () => setState(() => _passwordExpanded = !_passwordExpanded),
    ),
    if (_passwordExpanded) ...[
      const SizedBox(height: 6),
      _editInput(_passwordCtrl, 'Yeni şifrenizi girin', obscure: true),
      const SizedBox(height: 5),
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Boş bırakırsanız şifreniz değişmez.',
          style: TextStyle(fontSize: 11, color: kTextSecondary),
        ),
      ),
    ],
  ]);

  Widget _editTab(
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0753CD) : const Color(0xFFF0F3FA),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: active ? Colors.white : const Color(0xFF4E638D),
            size: 16,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: active ? Colors.white : const Color(0xFF4E638D),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _otherRow(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool destructive = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: const Color(0xFFF8FBFF),
      borderRadius: BorderRadius.circular(13),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: destructive
              ? const Color(0xFFFFE4E8)
              : const Color(0xFFE2F0FF),
          child: Icon(
            icon,
            color: destructive ? kDestructive : const Color(0xFF1269DB),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: destructive ? kDestructive : const Color(0xFF07164A),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 20,
          color: Color(0xFF07164A),
        ),
      ),
    ),
  );

  Widget _editRow(
    IconData icon,
    String label,
    TextEditingController controller,
    String hint,
    TextInputType keyboard,
  ) => Row(
    children: [
      CircleAvatar(
        radius: 17,
        backgroundColor: const Color(0xFFE2F0FF),
        child: Icon(icon, color: const Color(0xFF1269DB), size: 17),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 62,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF405680)),
        ),
      ),
      Expanded(child: _editInput(controller, hint, keyboard: keyboard)),
    ],
  );

  Widget _editInput(
    TextEditingController ctrl,
    String hint, {
    bool obscure = false,
    TextInputType? keyboard,
  }) => TextField(
    controller: ctrl,
    obscureText: obscure,
    keyboardType: keyboard,
    decoration: InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
    ),
  );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}
