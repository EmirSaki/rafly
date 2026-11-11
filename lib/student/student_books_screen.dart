import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../main.dart';

class StudentBooksScreen extends StatefulWidget {
  final String schoolCode;
  final VoidCallback? onBack;
  const StudentBooksScreen({super.key, required this.schoolCode, this.onBack});
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
  bool _availableOnly = false;
  String? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getSchoolBooks(
        schoolCode: widget.schoolCode,
        page: page,
        limit: 42,
        search: _searchCtrl.text.trim(),
      );

      final List books = (res["books"] as List?) ?? res["data"] ?? [];
      _books = books;
      _page = res['pagination']?['page'] ?? 1;
      _totalPages = res['pagination']?['totalPages'] ?? 1;
      _totalQuantity =
          res['summary']?['totalQuantity'] ?? res['totalQuantity'] ?? 0;
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final visibleBooks = _availableOnly
        ? _books.where((book) {
            final data = book is Map<String, dynamic>
                ? book
                : (book as dynamic).toJson() as Map<String, dynamic>;
            return (int.tryParse('${data['available_quantity'] ?? 0}') ?? 0) >
                0;
          }).toList()
        : _books;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8FF),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  _topButton(
                    Icons.arrow_back,
                    widget.onBack ?? () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Kitap Listesi',
                      style: TextStyle(
                        color: Color(0xFF07164A),
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1880A9DD),
                          blurRadius: 13,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Kitap veya yazar ara...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF1769D9),
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _topButton(
                  Icons.tune_rounded,
                  () => showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: SwitchListTile(
                        title: const Text('Bu sayfada mevcut olanlar'),
                        value: _availableOnly,
                        onChanged: (value) {
                          setState(() => _availableOnly = value);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 18,
                  color: Color(0xFF5F75A3),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Toplam: $_totalQuantity adet kitap',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF405680),
                    ),
                  ),
                ),
                Text(
                  'Sayfa $_page / $_totalPages',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5F75A3),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: _page > 1 ? () => _fetch(page: _page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: _page < _totalPages
                      ? () => _fetch(page: _page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  )
                : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : visibleBooks.isEmpty
                ? const Center(
                    child: Text(
                      'Kitap bulunamadı',
                      style: TextStyle(color: kTextSecondary),
                    ),
                  )
                : RefreshIndicator(
                    color: kPrimary,
                    onRefresh: () => _fetch(page: _page),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      itemCount: visibleBooks.length,
                      itemBuilder: (_, i) => _bookTile(visibleBooks[i]),
                    ),
                  ),
          ),
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pageButton(
                    '‹',
                    _page > 1 ? () => _fetch(page: _page - 1) : null,
                  ),
                  const SizedBox(width: 8),
                  for (final p in _visiblePages()) ...[
                    _pageButton(
                      '$p',
                      () => _fetch(page: p),
                      active: p == _page,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_totalPages > 5) const Text('…'),
                  const SizedBox(width: 6),
                  _pageButton(
                    '›',
                    _page < _totalPages ? () => _fetch(page: _page + 1) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bookTile(dynamic book) {
    final data = book is Map<String, dynamic>
        ? book
        : (book as dynamic).toJson();
    final title = data['title'] ?? data['book_name'] ?? 'Bilinmeyen';
    final authors = data['authors'] is List
        ? (data['authors'] as List).join(', ')
        : (data['authors'] ?? '').toString();
    final publisher = data['publisher'] ?? '';
    final qty = data['quantity'] ?? 0;
    final available =
        data['available_quantity'] ?? data['availableQuantity'] ?? 0;

    return GestureDetector(
      onTap: () => _showBook(data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white, width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1484A5D2),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _cover((data['cover_url'] ?? data['coverUrl'] ?? '').toString()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF07164A),
                    ),
                  ),
                  if (authors.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.person,
                          size: 13,
                          color: Color(0xFF758AB4),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            authors,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF697B9E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (publisher.toString().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance,
                          size: 13,
                          color: Color(0xFF758AB4),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            publisher.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF697B9E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF5FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '$available/$qty',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF082D81),
                    ),
                  ),
                  const Text(
                    'mevcut',
                    style: TextStyle(fontSize: 10, color: Color(0xFF697B9E)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Color(0xFF758AB4), size: 19),
          ],
        ),
      ),
    );
  }

  void _showBook(Map<String, dynamic> book) {
    final detail = Book.fromJson(book);
    final shelfText = detail.shelves.isNotEmpty
        ? detail.shelves.join(', ')
        : 'Belirtilmemiş';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.title.isEmpty ? 'Kitap' : detail.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF07164A),
                ),
              ),
              const SizedBox(height: 12),
              Text('Yazar: ${detail.authors.isEmpty ? '-' : detail.authors.join(', ')}'),
              Text('Yayınevi: ${book['publisher'] ?? '-'}'),
              Text('ISBN: ${book['isbn'] ?? '-'}'),
              Text('Raf Konumu: $shelfText'),
              Text(
                'Mevcut: ${book['available_quantity'] ?? 0}/${book['quantity'] ?? 0}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(String? rawUrl) {
    final url = (rawUrl ?? '').trim();
    const double w = 51, h = 70;

    Widget placeholder() => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: kMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: kPrimary, size: 22),
      ),
    );

    if (url.isEmpty) return placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: w,
            height: h,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _topButton(IconData icon, VoidCallback onTap) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    elevation: 2,
    shadowColor: const Color(0xFFB0C9EA),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFF1262D2)),
      iconSize: 22,
      padding: const EdgeInsets.all(12),
    ),
  );

  List<int> _visiblePages() {
    final start = _totalPages <= 5 ? 1 : (_page - 2).clamp(1, _totalPages - 4);
    final end = _totalPages <= 5 ? _totalPages : start + 4;
    return [for (var p = start; p <= end; p++) p];
  }

  Widget _pageButton(String label, VoidCallback? onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 35),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2975EE) : kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active
                ? Colors.white
                : onTap == null
                ? kTextSecondary
                : kPrimary,
          ),
        ),
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
