import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../main.dart';
import 'book_detail_page.dart';

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

  Future<void> exportBooks(String format) async {
    try {
      final path = await ApiService.exportBooks(
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
          hintText: 'Kitap adı veya yazar ara...',
          prefixIcon: const Icon(Icons.search, color: kTextSecondary),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.library_books_outlined,
                  color: kPrimary, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Toplam Kitap Adedi",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: kTextSecondary,
                ),
              ),
            ),
            Text(
              "$totalQuantity",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    final canGoPrevious = currentPage > 1 && !isLoading;
    final canGoNext = currentPage < totalPages && !isLoading;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  canGoPrevious ? () => loadBooks(page: currentPage - 1) : null,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text("Önceki"),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "Sayfa $currentPage / $totalPages",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kTextSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  canGoNext ? () => loadBooks(page: currentPage + 1) : null,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text("Sonraki"),
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: book.bookId == null
              ? null
              : () async {
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookDetailPage(
                        schoolCode: widget.schoolCode,
                        book: book,
                      ),
                    ),
                  );
                  if (changed == true) await refreshBooks();
                },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isOutOfStock
                    ? kDestructive.withValues(alpha: 0.3)
                    : kBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text("Yazar: ",
                              style: TextStyle(
                                  fontSize: 13, color: kTextSecondary)),
                          Flexible(
                            child: highlightText(authorsText, query),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ISBN: ${book.isbn.isNotEmpty ? book.isbn : "Yok"}',
                        style: const TextStyle(
                            fontSize: 12, color: kTextSecondary),
                      ),
                      Text(
                        'Yayınevi: ${book.publisher.isNotEmpty ? book.publisher : "Bilinmiyor"}',
                        style: const TextStyle(
                            fontSize: 12, color: kTextSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Stok: $quantity',
                      style: const TextStyle(
                          fontSize: 12, color: kTextSecondary),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOutOfStock
                            ? kDestructive.withValues(alpha: 0.08)
                            : kSuccess.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
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
        title: const Text('Kitap Listesi'),
        actions: [
          PopupMenuButton<String>(
            onSelected: exportBooks,
            icon: const Icon(Icons.download_outlined),
            itemBuilder: (context) => const [
              PopupMenuItem(value: "excel", child: Text("Excel indir")),
              PopupMenuItem(value: "pdf", child: Text("PDF indir")),
            ],
          ),
        ],
      ),
      backgroundColor: kBackground,
      body: Column(
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
      ),
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
