import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
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
  final TextEditingController categoriesController = TextEditingController();
  String coverUrl = "";
  final TextEditingController volumeCountController =
      TextEditingController(text: "0");
  final TextEditingController quantityController =
      TextEditingController(text: "1");
  final TextEditingController pageCountController = TextEditingController();
  final TextEditingController shelfController = TextEditingController();

  bool isLoading = false;
  String statusMessage = "";
  Map<String, dynamic>? bookData;
  bool showForm = false;
  bool isValilikBook = false;

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
      categoriesController.text =
          ApiService.normalizeStringList(data["categories"]).join(", ");
      coverUrl = (data["coverUrl"] ?? "").toString();
      pageCountController.text = '${data["pageCount"] ?? 0}';
      volumeCountController.text = '${data["volumeCount"] ?? 0}';
      quantityController.text = "1";

      setState(() {
        bookData = data;
        showForm = true;
        isValilikBook = data["isValilikBook"] == true;
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
        categoriesController.clear();
        coverUrl = "";
        pageCountController.clear();
        volumeCountController.text = "0";
        quantityController.text = "1";
        isValilikBook = false;
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
    final categories =
        ApiService.normalizeStringList(categoriesController.text).toList();
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
          "coverUrl": coverUrl,
          "physicalDescription": pageCount > 0 ? "$pageCount sayfa" : "",
          "shelf": shelfController.text.trim(),
          "isValilikBook": isValilikBook,
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

  Widget _buildValilikCheckbox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: CheckboxListTile(
          value: isValilikBook,
          onChanged: (value) =>
              setState(() => isValilikBook = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          dense: true,
          title: const Text(
            "Valilik Kitabı",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
            ),
          ),
          subtitle: const Text(
            "Bu kitap valilik tarafından sağlandıysa işaretleyin.",
            style: TextStyle(fontSize: 12, color: kTextSecondary),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    isbnController.dispose();
    titleController.dispose();
    authorsController.dispose();
    publisherController.dispose();
    categoriesController.dispose();
    volumeCountController.dispose();
    quantityController.dispose();
    pageCountController.dispose();
    shelfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6FAFF),
        body: SafeArea(
          child: Stack(children: [
          Positioned(top: -180, left: -160, child: Container(width: 460, height: 340,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE2F0FF)))),
          Positioned(bottom: -150, left: -100, child: Container(width: 540, height: 250,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFB9DBFA)))),
          Positioned(bottom: -180, left: -120, child: Container(width: 560, height: 250,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF66ADED)))),
          Positioned(bottom: -210, left: -130, child: Container(width: 560, height: 250,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2778CC)))),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Material(color: Colors.white, shape: const CircleBorder(), elevation: 3,
                    child: IconButton(onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF061F58)))),
                  const SizedBox(width: 13),
                  const Text('Manuel Ekleme', style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w700, color: Color(0xFF061F58))),
                ]),
                const SizedBox(height: 78),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF0F6FF),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFE6F0FD)),
                    boxShadow: const [BoxShadow(color: Color(0x131F69B4), blurRadius: 20, offset: Offset(0, 8))]),
                  child: Row(children: [
                    Container(width: 65, height: 65,
                      decoration: BoxDecoration(color: const Color(0xFFD9EAFD), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.edit_note_rounded, color: Color(0xFF1F68BB), size: 37)),
                    const SizedBox(width: 14),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Manuel Kitap Ekleme', style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700, color: Color(0xFF061F58))),
                      SizedBox(height: 4),
                      Text('ISBN numarası ile kitap bilgilerini manuel olarak getirebilirsiniz.',
                        style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF697892))),
                    ])),
                    const SizedBox(width: 6),
                    const Icon(Icons.auto_stories_rounded, color: Color(0xFF397FCC), size: 65),
                  ]),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [BoxShadow(color: Color(0x151F69B4), blurRadius: 21, offset: Offset(0, 7))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "ISBN ile Ara",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF061F58),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        "ISBN numarası girerek kitap bilgilerini otomatik getir",
                        style: TextStyle(fontSize: 12, color: Color(0xFF697892)),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: isbnController,
                        keyboardType: TextInputType.text,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF061F58),
                        ),
                        decoration: InputDecoration(
                          hintText: "9789756227740",
                          prefixIcon: const Icon(Icons.menu_book_outlined, color: Color(0xFF061F58)),
                          suffixIcon: isbnController.text.isEmpty ? null : IconButton(
                            onPressed: () => setState(isbnController.clear),
                            icon: const Icon(Icons.cancel_rounded, color: Color(0xFFA5B0C7))),
                          filled: true, fillColor: Colors.white,
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                            borderSide: const BorderSide(color: Color(0xFF90C5FA))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                            borderSide: const BorderSide(color: Color(0xFF4F9CEC), width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 49,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : searchBookByIsbn,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1466B8),
                            foregroundColor: Colors.white, shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                          child: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.search_rounded, size: 26), SizedBox(width: 9),
                                  Text('Ara', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))]),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFF0F6FF),
                          borderRadius: BorderRadius.circular(10)),
                        child: const Row(children: [Icon(Icons.info_rounded, color: Color(0xFF258BF3)),
                          SizedBox(width: 10), Expanded(child: Text(
                            'Lütfen 10 veya 13 haneli ISBN numarasını giriniz.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF697892))))])),
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
                        if (coverUrl.trim().isNotEmpty) ...[
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                coverUrl,
                                height: 160,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
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
                        _buildFormField(
                          label: "Kategoriler (virgülle ayır)",
                          controller: categoriesController,
                          textCapitalization: TextCapitalization.words,
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
                        _buildFormField(
                          label: "Raf (opsiyonel)",
                          controller: shelfController,
                          textCapitalization: TextCapitalization.characters,
                        ),
                        _buildValilikCheckbox(),
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
          ]),
        ),
      ),
    );
  }
}
