import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../services/api_service.dart';

class CreateAnnouncementPage extends StatefulWidget {
  final String schoolCode;

  const CreateAnnouncementPage({super.key, required this.schoolCode});

  @override
  State<CreateAnnouncementPage> createState() => _CreateAnnouncementPageState();
}

class _CreateAnnouncementPageState extends State<CreateAnnouncementPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  String _targetType = 'all';
  final List<String> _targetValues = [];
  final _targetValueController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  final List<Uint8List> _selectedImages = [];
  bool _isSending = false;

  final List<Map<String, String>> _targetTypes = const [
    {'value': 'all', 'label': 'Tüm Öğrenciler'},
    {'value': 'school_level', 'label': 'Okul Seviyesi'},
    {'value': 'class', 'label': 'Sınıf'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _targetValueController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (picked.isEmpty) return;

    for (final xFile in picked) {
      final bytes = await xFile.readAsBytes();
      _selectedImages.add(bytes);
    }

    setState(() {});
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _addTargetValue() {
    final value = _targetValueController.text.trim();
    if (value.isEmpty) return;
    if (_targetValues.contains(value.toUpperCase())) return;
    setState(() {
      _targetValues.add(value.toUpperCase());
      _targetValueController.clear();
    });
  }

  void _removeTargetValue(String value) {
    setState(() => _targetValues.remove(value));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 7));
        }
      } else {
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başlık ve içerik zorunludur')),
      );
      return;
    }

    if (_targetType != 'all' && _targetValues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hedef değerleri ekleyin')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      List<String>? imageBase64List;
      if (_selectedImages.isNotEmpty) {
        imageBase64List = _selectedImages.map((bytes) {
          final b64 = base64Encode(bytes);
          return 'data:image/jpeg;base64,$b64';
        }).toList();
      }

      await ApiService.createAnnouncement(
        schoolCode: widget.schoolCode,
        title: title,
        content: content,
        targetType: _targetType,
        targetValues: _targetType == 'all' ? [] : _targetValues,
        startDate: _formatDate(_startDate),
        endDate: _formatDate(_endDate),
        imageBase64List: imageBase64List,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bildirim gönderildi'),
          backgroundColor: kSuccess,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: kDestructive,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFEAF5FF),
        toolbarHeight: 78,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bildirim Gönder', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF07164A))),
          Text('Öğrencilere duyuru veya uyarı gönderebilirsiniz.', style: TextStyle(fontSize: 12, color: kTextSecondary)),
        ]),
        actions: const [Padding(padding: EdgeInsets.only(right: 18), child: Icon(Icons.campaign, color: Color(0xFF1269D8), size: 30))],
      ),
      backgroundColor: const Color(0xFFEAF5FF),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading(Icons.description_outlined, 'Başlık', 'Duyuru başlığını girin.'),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(hintText: 'Duyuru başlığı'),
            ),
            const SizedBox(height: 24),
            _sectionHeading(Icons.chat_bubble_outline, 'İçerik', 'Duyuru içeriğini girin.'),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(hintText: 'Duyuru içeriği...', fillColor: Colors.white, filled: true),
            ),
            const SizedBox(height: 16),
            _sectionHeading(Icons.people_alt_outlined, 'Hedef Kitle', 'Bildirim gönderilecek öğrenci grubunu seçin.'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _targetType,
              items: _targetTypes.map((t) {
                return DropdownMenuItem(value: t['value'], child: Text(t['label']!));
              }).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _targetType = v;
                  _targetValues.clear();
                });
              },
            ),
            if (_targetType != 'all') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetValueController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: _targetType == 'school_level'
                            ? 'örn: ortaokul, lise'
                            : 'örn: 5A, 6B',
                      ),
                      onSubmitted: (_) => _addTargetValue(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addTargetValue,
                    icon: const Icon(Icons.add_circle, color: kPrimary),
                  ),
                ],
              ),
              if (_targetValues.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _targetValues.map((v) {
                    return Chip(
                      label: Text(v, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => _removeTargetValue(v),
                    );
                  }).toList(),
                ),
              ],
            ],
            const SizedBox(height: 24),
            _sectionHeading(Icons.calendar_month_outlined, 'Tarih Aralığı', 'Bildirimde geçerli olacak tarih aralığını seçin.'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Başlangıç'),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: true),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_formatDate(_startDate)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Bitiş'),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: false),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_formatDate(_endDate)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionHeading(Icons.image_outlined, 'Fotoğraflar', 'Duyuruya görsel ekleyebilirsiniz (isteğe bağlı).'),
            const SizedBox(height: 8),
            if (_selectedImages.isNotEmpty) ...[
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _selectedImages[i],
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(i),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            InkWell(onTap: _pickImages, child: Container(
              width: double.infinity, height: 102,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF9BC9F6)), color: Colors.white.withValues(alpha: .45)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF1269D8), size: 30),
                Text(_selectedImages.isEmpty ? 'Fotoğraf Ekle' : 'Daha Fazla Ekle', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF07164A))),
                const Text('JPG, PNG formatında görseller ekleyebilirsiniz', style: TextStyle(fontSize: 11, color: kTextSecondary)),
              ]),
            )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _send,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0753CD), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.send),
                label: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Gönder'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary),
    );
  }

  Widget _sectionHeading(IconData icon, String title, String subtitle) => Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFDDEEFF), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: const Color(0xFF0753CD))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF07164A))),
      Text(subtitle, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
    ])),
  ]);
}
