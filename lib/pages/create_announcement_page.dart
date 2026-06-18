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
      appBar: AppBar(title: const Text('Bildirim Gönder')),
      backgroundColor: kBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Başlık'),
            const SizedBox(height: 4),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(hintText: 'Duyuru başlığı'),
            ),
            const SizedBox(height: 16),
            _label('İçerik'),
            const SizedBox(height: 4),
            TextField(
              controller: _contentController,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Duyuru içeriği'),
            ),
            const SizedBox(height: 16),
            _label('Hedef Kitle'),
            const SizedBox(height: 4),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 20),
            _label('Fotoğraflar'),
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
            OutlinedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_selectedImages.isEmpty ? 'Fotoğraf Ekle' : 'Daha Fazla Ekle'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSending ? null : _send,
                child: _isSending
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
}
