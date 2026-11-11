import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../main.dart';
import 'book_detail_page.dart';
import 'isbn_scan_page.dart';

class BookListPage extends StatefulWidget {
  final String schoolCode;

  const BookListPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Book> books = [];

  int currentPage = 1;
  final int limit = 30;
  int totalPages = 1;
  int totalBooks = 0;
  int totalQuantity = 0;

  bool isLoading = false;
  bool isInitialLoading = true;

  String currentSearch = "";
  Timer? _debounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    loadBooks(page: 1);
    searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  String normalizeTurkish(String text) {
    return ApiService.normalizeTurkishText(text);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final newSearch = searchController.text.trim();
      if (newSearch != currentSearch) {
        setState(() {
          currentSearch = newSearch;
          currentPage = 1;
          books = [];
          isInitialLoading = true;
        });
        loadBooks(page: 1);
      }
    });
  }

  Future<void> loadBooks({int? page}) async {
    if (isLoading) return;

    final int activeRequestId = ++_requestId;
    final int pageToLoad = page ?? currentPage;
    final String searchToUse = currentSearch;

    setState(() {
      isLoading = true;
      if (books.isEmpty) isInitialLoading = true;
    });

    try {
      final result = await ApiService.getSchoolBooks(
        schoolCode: widget.schoolCode,
        page: pageToLoad,
        limit: limit,
        search: searchToUse,
      );

      if (!mounted || activeRequestId != _requestId) return;

      final List<Book> newBooks = result["books"] as List<Book>;
      final pagination = result["pagination"] as Map<String, dynamic>;
      final newTotalQuantity = result["totalQuantity"] ?? 0;

      setState(() {
        books = newBooks;
        currentPage =
            int.tryParse('${pagination["page"] ?? pageToLoad}') ?? pageToLoad;
        totalPages = int.tryParse('${pagination["totalPages"] ?? 1}') ?? 1;
        totalBooks = int.tryParse('${pagination["total"] ?? 0}') ?? 0;
        totalQuantity = int.tryParse('$newTotalQuantity') ?? 0;
      });

      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted || activeRequestId != _requestId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: $e")),
      );
    } finally {
      if (!mounted || activeRequestId != _requestId) return;
      setState(() {
        isLoading = false;
        isInitialLoading = false;
      });
    }
  }

  Future<void> refreshBooks() async {
    await loadBooks(page: currentPage);
  }

  // Barkod tara → kitap okul envanterinde varsa künyesini aç, yoksa bilgilendir.
  Future<void> _scanAndFind() async {
    final isbn = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const IsbnScanPage()),
    );
    if (!mounted || isbn == null || isbn.trim().isEmpty) return;

    // Kısa bir yükleniyor göstergesi
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await ApiService.fetchSchoolBookByIsbn(
        schoolCode: widget.schoolCode,
        isbn: isbn,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // yükleniyor dialog'unu kapat

      final book = Book.fromJson(data);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BookDetailPage(schoolCode: widget.schoolCode, book: book),
        ),
      );
      if (mounted) await refreshBooks();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // yükleniyor dialog'unu kapat

      final msg = e.toString().toLowerCase();
      final notFound = msg.contains("bulunamad");
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(notFound ? "Kitap Bulunamadı" : "Hata"),
          content: Text(
            notFound
                ? "ISBN: $isbn\n\nBu kitap henüz kütüphaneye eklenmedi."
                : e.toString().replaceFirst("Exception: ", ""),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Tamam"),
            ),
          ],
        ),
      );
    }
  }

  Future<void> exportBooks(String format) async {
    try {
      await ApiService.exportBooks(
        schoolCode: widget.schoolCode,
        format: format,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            format == "excel"
                ? "Excel Downloads klasörüne kaydedildi"
                : "PDF Downloads klasörüne kaydedildi",
          ),
          action: SnackBarAction(label: "Tamam", onPressed: () {}),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Export hatası: $e")),
      );
    }
  }

  List<_MatchRange> _findNormalizedMatches(String originalText, String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || originalText.isEmpty) return [];

    final normalizedTextBuffer = StringBuffer();
    final List<int> normalizedIndexToOriginalIndex = [];

    for (int i = 0; i < originalText.length; i++) {
      final normalizedChar = normalizeTurkish(originalText[i]);
      normalizedTextBuffer.write(normalizedChar);
      for (int j = 0; j < normalizedChar.length; j++) {
        normalizedIndexToOriginalIndex.add(i);
      }
    }

    final normalizedText = normalizedTextBuffer.toString();
    final normalizedQuery = normalizeTurkish(trimmedQuery);

    if (normalizedQuery.isEmpty) return [];

    final matches = <_MatchRange>[];
    int searchStart = 0;

    while (searchStart < normalizedText.length) {
      final matchIndex = normalizedText.indexOf(normalizedQuery, searchStart);
      if (matchIndex == -1) break;

      final originalStart = normalizedIndexToOriginalIndex[matchIndex];
      final normalizedEndIndex = matchIndex + normalizedQuery.length - 1;
      final originalEnd =
          normalizedIndexToOriginalIndex[normalizedEndIndex] + 1;

      matches.add(_MatchRange(start: originalStart, end: originalEnd));
      searchStart = matchIndex + normalizedQuery.length;
    }

    return matches;
  }

  Widget highlightText(String text, String query) {
    if (query.trim().isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: kTextPrimary,
        ),
      );
    }

    final matches = _findNormalizedMatches(text, query);

    if (matches.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: kTextPrimary,
        ),
      );
    }

    final spans = <TextSpan>[];
    int currentIndex = 0;

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: const TextStyle(
            color: kPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: kTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: TextField(
        controller: searchController,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.words,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(r"[a-zA-Z0-9ğüşöçıİĞÜŞÖÇ\s\.\-:,'()]"),
          ),
        ],
        decoration: InputDecoration(
          hintText: 'Kitap adı, yazar veya ISBN ara...',
          hintStyle: const TextStyle(color: Color(0xFF5E7093), fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF46618F), size: 26),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .92),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9E8F8))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF76B8F7), width: 1.5)),
          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: kTextSecondary),
                  onPressed: () => searchController.clear(),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildTotalQuantityCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF8FCFF), Color(0xFFD1E8FF), Color(0xFFC2E1FF)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white),
          boxShadow: const [BoxShadow(color: Color(0x28558FD0), blurRadius: 13, offset: Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFC7E4FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.library_books_outlined,
                  color: Color(0xFF1269C8), size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Toplam Kitap Adedi', style: TextStyle(fontSize: 13, color: Color(0xFF102E67))),
              Text('$totalQuantity', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800,
                color: Color(0xFF071E52))),
            ])),
            const Icon(Icons.auto_stories_rounded, size: 65, color: Color(0xFF267FDB)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    final canGoPrevious = currentPage > 1 && !isLoading;
    final canGoNext = currentPage < totalPages && !isLoading;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Color(0x22558FD0), blurRadius: 16, offset: Offset(0, 5))]),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed:
                  canGoPrevious ? () => loadBooks(page: currentPage - 1) : null,
              style: TextButton.styleFrom(backgroundColor: const Color(0xFFE8F4FF),
                foregroundColor: const Color(0xFF4770A2), padding: const EdgeInsets.symmetric(vertical: 13)),
              icon: const Icon(Icons.chevron_left, size: 22),
              label: const Text("Önceki"),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "Sayfa $currentPage / $totalPages",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0B2A66),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextButton(
              onPressed:
                  canGoNext ? () => loadBooks(page: currentPage + 1) : null,
              style: TextButton.styleFrom(backgroundColor: const Color(0xFF0A5BB9),
                foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Sonraki'), SizedBox(width: 4), Icon(Icons.chevron_right, size: 22)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverThumb(Book book) {
    final url = (book.coverUrl ?? "").trim();
    const double w = 62, h = 74;

    Widget placeholder() => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder),
          ),
          child: const Icon(Icons.menu_book_outlined,
              size: 20, color: kTextSecondary),
        );

    if (url.isEmpty) return placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
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

  Widget _buildBookCard(Book book, String query) {
    final authorsText =
        book.authors.isNotEmpty ? book.authors.join(", ") : "Bilinmiyor";

    final quantity = book.quantity ?? 0;
    final availableQuantity = book.availableQuantity ?? 0;
    final isOutOfStock = availableQuantity <= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: const Color(0xFFDDEEFF),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: book.bookId == null
              ? null
              : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookDetailPage(
                        schoolCode: widget.schoolCode,
                        book: book,
                      ),
                    ),
                  );
                  // Detaydan dönünce listeyi her zaman tazele: kapak yükleme
                  // gibi değişiklikler de (pop sonucu dönmese bile) yansısın.
                  if (mounted) await refreshBooks();
                },
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: isOutOfStock
                    ? kDestructive.withValues(alpha: 0.3)
                    : Colors.white,
              ),
              boxShadow: const [BoxShadow(color: Color(0x1E5F9AD1), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildCoverThumb(book),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      highlightText(
                        book.title.isNotEmpty
                            ? book.title
                            : 'Bilinmeyen Kitap',
                        query,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 13, color: Color(0xFF4A669A)),
                          const SizedBox(width: 4),
                          const Text("Yazar: ", style: TextStyle(fontSize: 11, color: Color(0xFF5C7195))),
                          Flexible(
                            child: highlightText(authorsText, query),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(children: [const Icon(Icons.view_week, size: 13, color: Color(0xFF4A669A)),
                        const SizedBox(width: 4), Expanded(child: Text(
                          'ISBN: ${book.isbn.isNotEmpty ? book.isbn : "Yok"}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF5C7195))))]),
                      const SizedBox(height: 3),
                      Row(children: [const Icon(Icons.apartment, size: 13, color: Color(0xFF4A669A)),
                        const SizedBox(width: 4), Expanded(child: Text(
                          'Yayınevi: ${book.publisher.isNotEmpty ? book.publisher : "Bilinmiyor"}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF5C7195))))]),
                      if (book.shelves.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.shelves,
                                size: 13, color: kTextSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                book.shelves.join(", "),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: kPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(width: 1, height: 45, color: const Color(0xFFB5D1EC)),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Stok: $quantity',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF5C7195)),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOutOfStock
                            ? kDestructive.withValues(alpha: 0.08)
                            : const Color(0xFFC9F8D5),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$availableQuantity',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isOutOfStock ? kDestructive : kSuccess,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF45608C), size: 23),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: const Color(0xFFE5F3FF),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 67,
        leading: Padding(padding: const EdgeInsets.only(left: 10),
          child: Material(color: Colors.white, shape: const CircleBorder(),
            elevation: 3, child: IconButton(onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF071E52))))),
        centerTitle: true,
        title: const Text('Kitap Listesi', style: TextStyle(fontSize: 19,
          fontWeight: FontWeight.w800, color: Color(0xFF071E52))),
        actions: [
          Material(color: Colors.white, borderRadius: BorderRadius.circular(12), elevation: 3,
            child: IconButton(tooltip: 'Barkod tara', onPressed: _scanAndFind,
              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0A4BA2)))),
          const SizedBox(width: 8),
          Material(color: const Color(0xFF0D65C2), borderRadius: BorderRadius.circular(12), elevation: 3,
            child: PopupMenuButton<String>(
            onSelected: exportBooks,
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            itemBuilder: (context) => const [
              PopupMenuItem(value: "excel", child: Text("Excel indir")),
              PopupMenuItem(value: "pdf", child: Text("PDF indir")),
            ],
          )),
          const SizedBox(width: 12),
        ],
      ),
      backgroundColor: const Color(0xFFEAF5FF),
      body: Container(decoration: const BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFE5F3FF), Color(0xFFF5FAFF)])), child: Column(
        children: [
          _buildSearchBar(),
          _buildTotalQuantityCard(),
          Expanded(
            child: isInitialLoading
                ? const Center(child: CircularProgressIndicator())
                : books.isEmpty
                    ? const Center(
                        child: Text(
                          'Hiç kitap bulunamadı.',
                          style: TextStyle(
                            fontSize: 14,
                            color: kTextSecondary,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: refreshBooks,
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: books.length,
                          itemBuilder: (context, index) {
                            return _buildBookCard(books[index], query);
                          },
                        ),
                      ),
          ),
          _buildPaginationBar(),
        ],
      )),
    );
  }
}

class _MatchRange {
  final int start;
  final int end;

  _MatchRange({
    required this.start,
    required this.end,
  });
}
