import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/category_multi_select.dart';
import '../main.dart';

class ManualBookPage extends StatefulWidget {
  final String schoolCode;

  const ManualBookPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<ManualBookPage> createState() => _ManualBookPageState();
}

class _ManualBookPageState extends State<ManualBookPage> {
  final TextEditingController isbnController = TextEditingController();
  final TextEditingController titleController = TextEditingController();
  final TextEditingController authorsController = TextEditingController();
  final TextEditingController publisherController = TextEditingController();
  List<String> selectedCategories = [];
  final TextEditingController volumeCountController =
      TextEditingController(text: "0");
  final TextEditingController quantityController =
      TextEditingController(text: "1");
  final TextEditingController pageCountController = TextEditingController();

  bool isLoading = false;
  String statusMessage = "";
  Map<String, dynamic>? bookData;
  bool showForm = false;

  Future<void> searchBookByIsbn() async {
    final isbn = ApiService.normalizeIsbn(isbnController.text);

    if (isbn.isEmpty) {
      setState(() => statusMessage = "ISBN girmen lazım");
      return;
    }

    if (isbn.length != 10 && isbn.length != 13) {
      setState(() => statusMessage = "ISBN 10 ya da 13 haneli olmalı");
      return;
    }

    try {
      setState(() {
        isLoading = true;
        statusMessage = "Kitap aranıyor...";
        bookData = null;
      });

      final data = await ApiService.fetchBookByIsbn(isbn);

      if (!mounted) return;

      isbnController.text = (data["isbn"] ?? isbn).toString();
      titleController.text = data["title"]?.toString() ?? "";
      authorsController.text =
          ApiService.normalizeStringList(data["authors"]).join(", ");
      publisherController.text = (data["publisher"]?.toString() ?? "");
      selectedCategories =
          ApiService.normalizeStringList(data["categories"]).toList();
      pageCountController.text = '${data["pageCount"] ?? 0}';
      volumeCountController.text = '${data["volumeCount"] ?? 0}';
      quantityController.text = "1";

      setState(() {
        bookData = data;
        showForm = true;
        statusMessage = "Kitap bulundu. Düzenleyip kaydedebilirsin.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        bookData = null;
        showForm = true;
        statusMessage = "Kitap bulunamadı. Bilgileri manuel girebilirsin.";
        titleController.clear();
        authorsController.clear();
        publisherController.clear();
        selectedCategories = [];
        pageCountController.clear();
        volumeCountController.text = "0";
        quantityController.text = "1";
      });
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> saveBook({bool increaseQuantity = false}) async {
    final isbn = ApiService.normalizeIsbn(isbnController.text);
    final title = titleController.text.trim();
    final authors =
        ApiService.normalizeStringList(authorsController.text).toList();
    final publisher = publisherController.text.trim();
    final categories = List<String>.from(selectedCategories);
    final volumeCount =
        int.tryParse(volumeCountController.text.trim()) ?? 0;
    final quantity = int.tryParse(quantityController.text.trim()) ?? 1;
    final pageCount = int.tryParse(pageCountController.text.trim()) ?? 0;

    if (isbn.isEmpty || (isbn.length != 10 && isbn.length != 13)) {
      setState(() => statusMessage = "Geçerli bir ISBN gir");
      return;
    }

    if (title.isEmpty) {
      setState(() => statusMessage = "Kitap adı boş olamaz");
      return;
    }

    if (quantity <= 0) {
      setState(() => statusMessage = "Adet en az 1 olmalı");
      return;
    }

    try {
      setState(() {
        isLoading = true;
        statusMessage =
            increaseQuantity ? "Adet artırılıyor..." : "Kitap kaydediliyor...";
      });

      final result = await ApiService.saveBook(
        bookData: {
          "title": title,
          "authors": authors,
          "publisher": publisher,
          "categories": categories,
          "isbn": isbn,
          "schoolCode": widget.schoolCode,
          "volumeCount": volumeCount,
          "quantity": quantity,
          "pageCount": pageCount,
          "physicalDescription": pageCount > 0 ? "$pageCount sayfa" : "",
        },
        increaseQuantity: increaseQuantity,
      );

      if (!mounted) return;

      if (result["success"] == true) {
        setState(() => statusMessage = result["message"] ?? "İşlem başarılı");
        return;
      }

      final alreadyExists = result["alreadyExistsInSchool"] == true ||
          result["alreadyExists"] == true;

      if (alreadyExists) {
        setState(() =>
            statusMessage = result["message"] ?? "Kitap zaten kayıtlı");
        await showIncreaseQuantityDialog();
        return;
      }

      setState(
          () => statusMessage = result["message"] ?? "Kitap kaydedilemedi");
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains("zaten var") ||
          errorMessage.contains("artırılsın") ||
          errorMessage.contains("zaten kayıtlı")) {
        setState(() => statusMessage = "Kitap zaten kayıtlı");
        await showIncreaseQuantityDialog();
        return;
      }

      setState(() => statusMessage = "Kaydetme hatası: $e");
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> showIncreaseQuantityDialog() async {
    final shouldIncrease = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Kitap Zaten Kayıtlı"),
          content: const Text(
              "Bu kitap okul envanterinde zaten var.\nAdet artırılsın mı?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Hayır"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Evet"),
            ),
          ],
        );
      },
    );

    if (shouldIncrease == true) {
      await saveBook(increaseQuantity: true);
    } else {
      if (!mounted) return;
      setState(() => statusMessage = "İşlem iptal edildi");
    }
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
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
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters ?? [],
            style: const TextStyle(fontSize: 14, color: kTextPrimary),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    isbnController.dispose();
    titleController.dispose();
    authorsController.dispose();
    publisherController.dispose();
    volumeCountController.dispose();
    quantityController.dispose();
    pageCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text("Manuel Ekleme")),
        backgroundColor: kBackground,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      const Text(
                        "ISBN ile Ara",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "ISBN numarası girerek kitap bilgilerini otomatik getir",
                        style: TextStyle(fontSize: 13, color: kTextSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: isbnController,
                        keyboardType: TextInputType.text,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: kTextPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: "9789756227740",
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : searchBookByIsbn,
                          child: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text("Ara"),
                        ),
                      ),
                    ],
                  ),
                ),
                if (statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    statusMessage,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: kTextSecondary,
                    ),
                  ),
                ],
                if (showForm) ...[
                  const SizedBox(height: 16),
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
                        const Text(
                          "Kitap Bilgileri",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildFormField(
                          label: "Kitap Adı",
                          controller: titleController,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        _buildFormField(
                          label: "Yazarlar (virgülle ayır)",
                          controller: authorsController,
                          textCapitalization: TextCapitalization.words,
                        ),
                        _buildFormField(
                          label: "Yayınevi",
                          controller: publisherController,
                          textCapitalization: TextCapitalization.words,
                        ),
                        CategoryMultiSelect(
                          label: "Kategoriler",
                          selected: selectedCategories,
                          onChanged: (list) =>
                              setState(() => selectedCategories = list),
                        ),
                        _buildFormField(
                          label: "Sayfa Sayısı",
                          controller: pageCountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textCapitalization: TextCapitalization.none,
                        ),
                        _buildFormField(
                          label: "Cilt Sayısı",
                          controller: volumeCountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textCapitalization: TextCapitalization.none,
                        ),
                        _buildFormField(
                          label: "Adet",
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textCapitalization: TextCapitalization.none,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : () => saveBook(),
                            child: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Kitabı Kaydet"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
