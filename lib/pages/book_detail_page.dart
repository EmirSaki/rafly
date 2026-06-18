import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import '../main.dart';

class BookDetailPage extends StatefulWidget {
  final String schoolCode;
  final Book book;

  const BookDetailPage({
    super.key,
    required this.schoolCode,
    required this.book,
  });

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController authorsController = TextEditingController();
  final TextEditingController publisherController = TextEditingController();
  final TextEditingController categoriesController = TextEditingController();
  final TextEditingController pageCountController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  String statusMessage = "";
  Book? book;

  @override
  void initState() {
    super.initState();
    loadBookDetail();
  }

  void _populateControllers(Book b) {
    quantityController.text = (b.quantity ?? 0).toString();
    authorsController.text = b.authors.join(", ");
    publisherController.text = b.publisher;
    categoriesController.text = b.categories.join(", ");
    pageCountController.text = b.pageCount > 0 ? b.pageCount.toString() : "";
  }

  Future<void> loadBookDetail() async {
    if (widget.book.bookId == null) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        book = widget.book;
      });
      _populateControllers(widget.book);
      return;
    }

    try {
      final loadedBook = await ApiService.getSchoolBookDetail(
        widget.schoolCode,
        widget.book.bookId!,
      );

      if (!mounted) return;

      setState(() {
        book = loadedBook;
        isLoading = false;
      });
      _populateControllers(loadedBook);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        book = widget.book;
        statusMessage = "Detay yüklenemedi: $e";
      });
      _populateControllers(widget.book);
    }
  }

  Future<void> saveBook() async {
    if (widget.book.bookId == null) {
      setState(() => statusMessage = "Kitap kimliği bulunamadı");
      return;
    }

    final quantity = int.tryParse(quantityController.text.trim());

    if (quantity == null || quantity < 0) {
      setState(() => statusMessage = "Geçerli bir adet gir");
      return;
    }

    final authors = authorsController.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final categories = categoriesController.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final pageCount = int.tryParse(pageCountController.text.trim()) ?? 0;

    try {
      setState(() {
        isSaving = true;
        statusMessage = "";
      });

      final result = await ApiService.updateSchoolBookQuantity(
        schoolCode: widget.schoolCode,
        bookId: widget.book.bookId!,
        quantity: quantity,
        authors: authors,
        publisher: publisherController.text.trim(),
        categories: categories,
        pageCount: pageCount,
      );

      if (!mounted) return;

      if (result["success"] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => statusMessage = result["message"] ?? "Güncellenemedi");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = "Hata: $e");
    } finally {
      if (!mounted) return;
      setState(() => isSaving = false);
    }
  }

  Future<void> deleteBook() async {
    if (widget.book.bookId == null) {
      setState(() => statusMessage = "Kitap kimliği bulunamadı");
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Kitabı Sil"),
          content: const Text(
            "Bu kitap sadece bu okulun envanterinden silinecek. Emin misin?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Vazgeç"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDestructive,
              ),
              child: const Text("Sil"),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      setState(() {
        isSaving = true;
        statusMessage = "";
      });

      final result = await ApiService.deleteSchoolBook(
        schoolCode: widget.schoolCode,
        bookId: widget.book.bookId!,
      );

      if (!mounted) return;

      if (result["success"] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => statusMessage = result["message"] ?? "Silinemedi");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = "Hata: $e");
    } finally {
      if (!mounted) return;
      setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    quantityController.dispose();
    authorsController.dispose();
    publisherController.dispose();
    categoriesController.dispose();
    pageCountController.dispose();
    super.dispose();
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: kMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 14, color: kTextPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(fontSize: 14, color: kTextPrimary),
            decoration: InputDecoration(
              hintText: hint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentBook = book ?? widget.book;

    return Scaffold(
      appBar: AppBar(title: const Text("Kitap Künyesi")),
      backgroundColor: kBackground,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          currentBook.title.isNotEmpty
                              ? currentBook.title
                              : "Kitap Detayı",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildReadOnlyField("Kitap Adı", currentBook.title),
                        _buildReadOnlyField(
                          "ISBN",
                          currentBook.isbn.isNotEmpty
                              ? currentBook.isbn
                              : "Yok",
                        ),
                        _buildEditableField(
                          label: "Yazar(lar)",
                          controller: authorsController,
                          hint: "Virgülle ayırarak yazın",
                        ),
                        _buildEditableField(
                          label: "Yayınevi",
                          controller: publisherController,
                        ),
                        _buildEditableField(
                          label: "Kategori",
                          controller: categoriesController,
                          hint: "Virgülle ayırarak yazın",
                        ),
                        _buildEditableField(
                          label: "Sayfa Sayısı",
                          controller: pageCountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        _buildEditableField(
                          label: "Kitap Adedi",
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        if (statusMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            statusMessage,
                            style: const TextStyle(
                              fontSize: 13,
                              color: kTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: isSaving ? null : saveBook,
                            child: isSaving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Kaydet"),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton(
                            onPressed: isSaving ? null : deleteBook,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kDestructive,
                              side: BorderSide(
                                  color: kDestructive.withValues(alpha: 0.3)),
                            ),
                            child: const Text("Kitabı Sil"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
