import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_auth_provider.dart';
import '../services/api_service.dart';
import '../main.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _editing = false;

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
        email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
        phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        context.read<StudentAuthProvider>().markProfileCompleted(res['data'] ?? {});
        _passwordCtrl.clear();
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil güncellendi'), backgroundColor: kSuccess),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Hata oluştu'), backgroundColor: kDestructive),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı hatası'), backgroundColor: kDestructive),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabımı Sil'),
        content: const Text(
          'Hesabın ve tüm kişisel verilerin (profil, ödünç geçmişi) kalıcı olarak silinecek. '
          'Bu işlem geri alınamaz.\n\nDevam etmek istiyor musun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kDestructive),
            child: const Text('Hesabımı Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await ApiService.deleteStudentAccount();
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesabın silindi'),
            backgroundColor: kSuccess,
          ),
        );
        await context.read<StudentAuthProvider>().logout();
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Hesap silinemedi'),
            backgroundColor: kDestructive,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bağlantı hatası'),
          backgroundColor: kDestructive,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<StudentAuthProvider>();
    final user = auth.user;
    final name = '${user?['user_name'] ?? ''} ${user?['user_surname'] ?? ''}'.trim();
    final studentNumber = user?['student_id'] ?? user?['student_number'] ?? '-';
    final userClass = user?['user_class'] ?? '-';

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 20, color: kTextSecondary),
              onPressed: () => setState(() => _editing = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20, color: kTextSecondary),
              onPressed: () {
                _loadProfile();
                _passwordCtrl.clear();
                setState(() => _editing = false);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kTextPrimary))),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Öğrenci No: $studentNumber  |  Sınıf: $userClass',
              style: const TextStyle(fontSize: 12, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 28),

          _infoCard([
            _infoRow('Okul Kodu', auth.schoolCode ?? '-'),
            _infoRow('Okul Seviyesi', auth.schoolLevel ?? '-'),
            _infoRow('Öğrenci No', studentNumber.toString()),
            _infoRow('Sınıf', userClass.toString()),
          ]),
          const SizedBox(height: 16),

          const Text('İLETİŞİM BİLGİLERİ',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 10),

          if (_editing) ...[
            _label('E-posta'),
            _editInput(_emailCtrl, 'ornek@email.com', keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _label('Telefon'),
            _editInput(_phoneCtrl, '05XX XXX XX XX', keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            _label('Yeni Şifre (opsiyonel)'),
            _editInput(_passwordCtrl, 'Boş bırakırsan değişmez', obscure: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Kaydet'),
              ),
            ),
          ] else ...[
            _infoCard([
              _infoRow('E-posta', _emailCtrl.text.isNotEmpty ? _emailCtrl.text : 'Eklenmemiş'),
              _infoRow('Telefon', _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : 'Eklenmemiş'),
            ]),
          ],

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () async => await auth.logout(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Çıkış Yap'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kDestructive,
                side: const BorderSide(color: kDestructive, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              onPressed: _loading ? null : _deleteAccount,
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Hesabımı Sil'),
              style: TextButton.styleFrom(foregroundColor: kDestructive),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: Column(children: children),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: kTextSecondary)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextPrimary)),
          ],
        ),
      );

  Widget _label(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextSecondary)),
        ),
      );

  Widget _editInput(TextEditingController ctrl, String hint, {bool obscure = false, TextInputType? keyboard}) => TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
      );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}
