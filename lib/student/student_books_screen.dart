import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../main.dart';

class StudentBooksScreen extends StatefulWidget {
  final String schoolCode;
  const StudentBooksScreen({super.key, required this.schoolCode});
  @override
  State<StudentBooksScreen> createState() => _StudentBooksScreenState();
}

class _StudentBooksScreenState extends State<StudentBooksScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<dynamic> _books = [];
  bool _loading = true;
  int _page = 1;
  int _totalPages = 1;
  int _totalQuantity = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _fetch();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetch();
    });
  }

  Future<void> _fetch({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getSchoolBooks(
        schoolCode: widget.schoolCode,
        page: page,
        limit: 30,
        search: _searchCtrl.text.trim(),
      );

      final List books = (res["books"] as List?) ?? res["data"] ?? [];
      _books = books;
      _page = res['pagination']?['page'] ?? 1;
      _totalPages = res['pagination']?['totalPages'] ?? 1;
      _totalQuantity = res['summary']?['totalQuantity'] ?? res['totalQuantity'] ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Kitap Listesi'),
      ),
      body: Column(
        children: [
          Container(
            color: kSurface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Kitap veya yazar ara...',
                      prefixIcon: const Icon(Icons.search_rounded, color: kTextSecondary, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text('Toplam: $_totalQuantity adet kitap', style: const TextStyle(fontSize: 12, color: kTextSecondary)),
                const Spacer(),
                Text('Sayfa $_page/$_totalPages', style: const TextStyle(fontSize: 12, color: kTextSecondary)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _books.isEmpty
                    ? const Center(child: Text('Kitap bulunamadı', style: TextStyle(color: kTextSecondary)))
                    : RefreshIndicator(
                        color: kPrimary,
                        onRefresh: () => _fetch(page: _page),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: _books.length,
                          itemBuilder: (_, i) => _bookTile(_books[i]),
                        ),
                      ),
          ),
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_page > 1) _pageButton('Önceki', () => _fetch(page: _page - 1)),
                  const SizedBox(width: 12),
                  if (_page < _totalPages) _pageButton('Sonraki', () => _fetch(page: _page + 1)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bookTile(dynamic book) {
    final data = book is Map<String, dynamic> ? book : (book as dynamic).toJson();
    final title = data['title'] ?? data['book_name'] ?? 'Bilinmeyen';
    final authors = data['authors'] is List ? (data['authors'] as List).join(', ') : (data['authors'] ?? '').toString();
    final publisher = data['publisher'] ?? '';
    final qty = data['quantity'] ?? 0;
    final available = data['available_quantity'] ?? data['availableQuantity'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 58,
            decoration: BoxDecoration(
              color: kMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Icon(Icons.menu_book_rounded, color: kPrimary, size: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary)),
                if (authors.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(authors, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: kTextSecondary)),
                ],
                if (publisher.toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(publisher.toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: kTextSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text('$available/$qty', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kPrimary)),
              const SizedBox(height: 2),
              const Text('mevcut', style: TextStyle(fontSize: 10, color: kTextSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pageButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary)),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }
}
