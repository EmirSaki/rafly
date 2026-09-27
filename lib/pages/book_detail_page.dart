import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  final TextEditingController shelfController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  bool isCoverUploading = false;
  String statusMessage = "";
  Book? book;

  @override
  void initState() {
    super.initState();
    loadBookDetail();
  }

  // ─── Kapak ───

  /// Kapak fotoğrafı seçtirir ve yükler.
  ///
  /// Kapak okula değil kitabın ISBN'ine bağlanır; aynı kitabı bulunduran
  /// bütün okullarda görünür. Bu yüzden yüklemeden önce onay alınır.
  Future<void> _pickAndUploadCover(ImageSource source) async {
    final isbn = (book ?? widget.book).isbn.trim();
    if (isbn.isEmpty) {
      setState(() => statusMessage = "Bu kitabın ISBN'i yok, kapak eklenemez");
      return;
    }

    final picker = ImagePicker();
    // Cihazda küçültülüp sıkıştırılır: hem yükleme hızlanır hem de
    // öğrencilerin mobil verisi boşa gitmez.
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 1200,
      imageQuality: 75,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final onayli = await _showCoverConfirmDialog(bytes);
    if (onayli != true || !mounted) return;

    setState(() {
      isCoverUploading = true;
      statusMessage = "Kapak yükleniyor...";
    });

    try {
      final result = await ApiService.uploadBookCover(
        isbn: isbn,
        imageBytes: bytes,
        fileName: picked.name.isNotEmpty ? picked.name : "kapak.jpg",
      );
      if (!mounted) return;

      setState(() {
        statusMessage = result["message"]?.toString() ?? "Kapak kaydedildi";
      });

      await loadBookDetail();
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          statusMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => isCoverUploading = false);
    }
  }

  Future<bool?> _showCoverConfirmDialog(Uint8List bytes) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Kapağı Yükle"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, height: 180, fit: BoxFit.contain),
            ),
            const SizedBox(height: 14),
            const Text(
              "Bu kapak, aynı kitabı bulunduran tüm okullarda görünecek.",
              style: TextStyle(fontSize: 13, color: kTextSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text("Vazgeç"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Yükle"),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseCoverSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text("Fotoğraf çek"),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text("Galeriden seç"),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) await _pickAndUploadCover(source);
  }

  Future<void> _removeCover() async {
    final isbn = (book ?? widget.book).isbn.trim();
    if (isbn.isEmpty) return;

    final onay = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Kapağı Kaldır"),
        content: const Text(
          "Bu kitabın kapağı tüm okullarda kaldırılacak. Devam edilsin mi?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text("Vazgeç"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Kaldır"),
          ),
        ],
      ),
    );

    if (onay != true || !mounted) return;

    setState(() {
      isCoverUploading = true;
      statusMessage = "Kapak kaldırılıyor...";
    });

    try {
      final result = await ApiService.deleteBookCover(isbn: isbn);
      if (!mounted) return;
      setState(() =>
          statusMessage = result["message"]?.toString() ?? "Kapak kaldırıldı");
      await loadBookDetail();
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          statusMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => isCoverUploading = false);
    }
  }

  Widget _buildCoverSection(Book currentBook) {
    final hasCover = (currentBook.coverUrl ?? "").trim().isNotEmpty;
    final busy = isCoverUploading || isSaving;

    return Column(
      children: [
        if (hasCover)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                currentBook.coverUrl!,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          )
        else
          Center(
            child: Container(
              height: 180,
              width: 130,
              decoration: BoxDecoration(
                color: kBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBorder),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 34, color: kTextSecondary),
                  SizedBox(height: 6),
                  Text(
                    "Kapak yok",
                    style: TextStyle(fontSize: 12, color: kTextSecondary),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (isCoverUploading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: busy ? null : _chooseCoverSource,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(hasCover ? "Kapağı Değiştir" : "Kapak Ekle"),
            ),
            if (hasCover)
              TextButton.icon(
                onPressed: busy ? null : _removeCover,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: kDestructive),
                label: const Text(
                  "Kaldır",
                  style: TextStyle(color: kDestructive),
                ),
              ),
          ],
        ),
        const Text(
          "Kapak, aynı kitabı bulunduran tüm okullarda görünür",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: kTextSecondary),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _populateControllers(Book b) {
    quantityController.text = (b.quantity ?? 0).toString();
    authorsController.text = b.authors.join(", ");
    publisherController.text = b.publisher;
    categoriesController.text = b.categories.join(", ");
    pageCountController.text = b.pageCount > 0 ? b.pageCount.toString() : "";
    shelfController.text = b.shelf ?? "";
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
        shelf: shelfController.text.trim(),
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
    shelfController.dispose();
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
                        _buildCoverSection(currentBook),
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
                        _buildEditableField(
                          label: "Raf",
                          controller: shelfController,
                          hint: "Örn: A-3 (boş bırakılabilir)",
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
