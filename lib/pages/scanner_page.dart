import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../main.dart';

class ScannerPage extends StatefulWidget {
  final String schoolCode;

  const ScannerPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool isScanned = false;
  bool isLoading = false;
  bool _isHandlingDetection = false;
  bool _torchOn = false;
  Timer? notFoundTimer;

  String statusMessage = "Barkodu okut";
  Map<String, dynamic>? bookData;
  bool isValilikBook = false;

  final TextEditingController shelfController = TextEditingController();
  final TextEditingController titleController = TextEditingController();
  final TextEditingController authorsController = TextEditingController();
  final TextEditingController publisherController = TextEditingController();
  final TextEditingController categoriesController = TextEditingController();
  final TextEditingController isbnController = TextEditingController();
  final TextEditingController pageCountController = TextEditingController();
  final TextEditingController volumeController =
      TextEditingController(text: "0");
  final TextEditingController quantityController =
      TextEditingController(text: "1");

  final MobileScannerController scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    startNotFoundTimer();

  }

  void startNotFoundTimer() {
    notFoundTimer?.cancel();
    notFoundTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (!isScanned && bookData == null) {
        setState(() {
          statusMessage = "Barkod bulunamadı";
        });
      }
    });
  }

  String normalizeIsbn(String value) {
    return value.replaceAll(RegExp(r'[^0-9Xx]'), '').trim();
  }

  bool isValidIsbnCandidate(String value) {
    final normalized = normalizeIsbn(value);
    return normalized.length == 10 || normalized.length == 13;
  }

  Future<void> fetchBook(String isbn) async {
    final normalizedIsbn = normalizeIsbn(isbn);

    if (!isValidIsbnCandidate(normalizedIsbn)) {
      if (!mounted) return;
      setState(() {
        bookData = null;
        titleController.clear();
        authorsController.clear();
        publisherController.clear();
        categoriesController.clear();
        isbnController.clear();
        pageCountController.clear();
        volumeController.text = "0";
        quantityController.text = "1";
        statusMessage = "Bu barkod geçerli bir ISBN gibi görünmüyor";
        isLoading = false;
        isScanned = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await scannerController.start();
        startNotFoundTimer();
      });
      return;
    }

    try {
      setState(() {
        isLoading = true;
        statusMessage = "Kitap sorgulanıyor...";
      });

      final data = await ApiService.fetchBookByIsbn(normalizedIsbn);

      if (!mounted) return;

      titleController.text = (data["title"]?.toString() ?? "");
      authorsController.text =
          ApiService.normalizeStringList(data["authors"]).join(", ");
      publisherController.text = (data["publisher"]?.toString() ?? "");
      categoriesController.text =
          ApiService.normalizeStringList(data["categories"]).join(", ");
      isbnController.text =
          normalizeIsbn((data["isbn"] ?? normalizedIsbn).toString());
      pageCountController.text = '${data["pageCount"] ?? 0}';
      volumeController.text = '${data["volumeCount"] ?? 0}';
      quantityController.text = "1";

      setState(() {
        bookData = data;
        isValilikBook = data["isValilikBook"] == true;
        statusMessage = "Kitap bulundu. Düzenleyip kaydedebilirsin.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        bookData = null;
        titleController.clear();
        authorsController.clear();
        publisherController.clear();
        categoriesController.clear();
        isbnController.text = normalizeIsbn(normalizedIsbn);
        pageCountController.clear();
        volumeController.text = "0";
        quantityController.text = "1";
        isValilikBook = false;
        statusMessage = "Kitap bulunamadı. Bilgileri düzenleyebilirsin.";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> saveBook({bool increaseQuantity = false}) async {
    final title = titleController.text.trim();
    final authors =
        ApiService.normalizeStringList(authorsController.text).toList();
    final publisher = publisherController.text.trim();
    final categories =
        ApiService.normalizeStringList(categoriesController.text).toList();
    final isbn = normalizeIsbn(isbnController.text);
    final volumeCount = int.tryParse(volumeController.text.trim()) ?? 0;
    final quantity = int.tryParse(quantityController.text.trim()) ?? 1;
    final pageCount = int.tryParse(pageCountController.text.trim()) ?? 0;

    if (title.isEmpty) {
      setState(() => statusMessage = "Kitap adı boş olamaz");
      return;
    }

    if (isbn.isEmpty || (isbn.length != 10 && isbn.length != 13)) {
      setState(() => statusMessage = "Geçerli ISBN gir");
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

      final decoded = await ApiService.saveBook(
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
          "shelf": shelfController.text.trim(),
          "isValilikBook": isValilikBook,
        },
        increaseQuantity: increaseQuantity,
      );

      if (!mounted) return;

      if (decoded["success"] == true) {
        setState(() {
          statusMessage = decoded["message"] ?? "İşlem başarılı";
        });
        return;
      }

      final alreadyExists = decoded["alreadyExists"] == true ||
          decoded["alreadyExistsInSchool"] == true;

      if (alreadyExists) {
        setState(() {
          statusMessage = decoded["message"] ?? "Kitap zaten kayıtlı";
        });
        await showIncreaseQuantityDialog();
        return;
      }

      setState(() {
        statusMessage = decoded["message"] ?? "Kitap kaydedilemedi";
      });
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

      setState(() {
        statusMessage = "Kaydetme hatası: $e";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
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

  Future<void> handleBarcode(String code) async {
    if (_isHandlingDetection || isLoading || isScanned) return;
    _isHandlingDetection = true;

    final normalizedCode = normalizeIsbn(code);
    notFoundTimer?.cancel();

    if (!isValidIsbnCandidate(normalizedCode)) {
      if (mounted) {
        setState(() => statusMessage = "Okunan barkod ISBN değil gibi duruyor");
      }
      _isHandlingDetection = false;
      return;
    }

    if (mounted) {
      setState(() {
        isLoading = true;
        statusMessage = "Barkod okundu: $normalizedCode";
      });
    }

    try {
      await scannerController.stop();
      await fetchBook(normalizedCode);
      if (!mounted) return;
      setState(() => isScanned = true);
    } finally {
      _isHandlingDetection = false;
    }
  }

  Future<void> resetScanner() async {
    FocusScope.of(context).unfocus();
    notFoundTimer?.cancel();

    setState(() {
      isScanned = false;
      isLoading = false;
      _isHandlingDetection = false;
      bookData = null;
      titleController.clear();
      authorsController.clear();
      publisherController.clear();
      categoriesController.clear();
      isbnController.clear();
      pageCountController.clear();
      volumeController.text = "0";
      quantityController.text = "1";
      shelfController.clear();
      statusMessage = "Barkodu okut";
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await scannerController.start();
      startNotFoundTimer();
    });
  }

  Widget buildScannerView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: scannerController,
          onDetect: (capture) async {
            if (_isHandlingDetection || isScanned || isLoading) return;
            for (final barcode in capture.barcodes) {
              final code = barcode.displayValue;
              if (code != null && code.isNotEmpty) {
                await handleBarcode(code);
                break;
              }
            }
          },
        ),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 16, 14, 0), child: Row(children: [
            Material(color: Colors.white, shape: const CircleBorder(), child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF09255A)), iconSize: 23)),
            const SizedBox(width: 12),
            const Expanded(child: Text('Barkod Tarama', style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700))),
            Material(color: const Color(0xB9000000), shape: const CircleBorder(), child: IconButton(
              onPressed: () async {
                await scannerController.toggleTorch();
                if (mounted) setState(() => _torchOn = !_torchOn);
              },
              icon: Icon(_torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                color: Colors.white), iconSize: 26)),
          ])),
          const SizedBox(height: 13),
          Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(color: const Color(0xC9000000), borderRadius: BorderRadius.circular(13)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.view_week_rounded, color: Color(0xFF67B6FF), size: 23),
              const SizedBox(width: 12),
              Text(statusMessage, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ])),
          const Spacer(),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 34),
            child: AspectRatio(aspectRatio: 1.05, child: CustomPaint(painter: _ScanFramePainter()))),
          const Spacer(),
          Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(30, 20, 24, 28),
            decoration: const BoxDecoration(color: Color(0xCC221B1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 34, height: 4,
                decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 15),
              const Row(children: [Icon(Icons.info_rounded, color: Color(0xFF2288F7), size: 27),
                SizedBox(width: 12), Text('Barkod Tarama İpuçları',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))]),
              const SizedBox(height: 12),
              _tip('Kitabın arkasındaki ISBN barkodunu okutun.'),
              _tip('Barkodu çerçeve içine hizalayın.'),
              _tip('Ortamın yeterince aydınlık olmasına dikkat edin.'),
            ])),
        ])),
        if (isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _tip(String text) => Padding(padding: const EdgeInsets.only(left: 42, bottom: 8),
    child: Row(children: [const Icon(Icons.check_circle_rounded, color: Color(0xFF318BE5), size: 21),
      const SizedBox(width: 10), Expanded(child: Text(text,
        style: const TextStyle(color: Color(0xFFE4E0E2), fontSize: 12)))]));

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

  Widget buildFormView() {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Barkod Okutuldu",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                statusMessage,
                style: const TextStyle(fontSize: 13, color: kTextSecondary),
              ),
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
                  children: [
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
                      label: "ISBN",
                      controller: isbnController,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    _buildFormField(
                      label: "Raf (opsiyonel)",
                      controller: shelfController,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    _buildFormField(
                      label: "Sayfa Sayısı",
                      controller: pageCountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textCapitalization: TextCapitalization.none,
                    ),
                    _buildFormField(
                      label: "Cilt Sayısı",
                      controller: volumeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textCapitalization: TextCapitalization.none,
                    ),
                    _buildFormField(
                      label: "Adet",
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textCapitalization: TextCapitalization.none,
                    ),
                    Padding(
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
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
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
                            style: TextStyle(
                                fontSize: 12, color: kTextSecondary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : saveBook,
                        child: isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text("Kitabı Kaydet"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: isLoading ? null : resetScanner,
                        child: const Text("Tekrar Tara"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    notFoundTimer?.cancel();
    shelfController.dispose();
    titleController.dispose();
    authorsController.dispose();
    publisherController.dispose();
    categoriesController.dispose();
    isbnController.dispose();
    pageCountController.dispose();
    volumeController.dispose();
    quantityController.dispose();
    scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: isScanned,
              child: buildScannerView(),
            ),
            if (isScanned) buildFormView(),
          ],
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final corner = Paint()..color = Colors.white..strokeWidth = 10
      ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    const length = 36.0;
    const inset = 8.0;
    for (final x in [inset, size.width - inset]) {
      for (final y in [inset, size.height - inset]) {
        final dx = x == inset ? 1.0 : -1.0;
        final dy = y == inset ? 1.0 : -1.0;
        final path = Path()..moveTo(x, y + length * dy)..lineTo(x, y)
          ..lineTo(x + length * dx, y);
        canvas.drawPath(path, corner);
      }
    }
    final bars = Paint()..color = Colors.white..strokeWidth = 6..strokeCap = StrokeCap.round;
    final start = size.width * .30;
    for (var i = 0; i < 11; i++) {
      final x = start + i * size.width * .04;
      canvas.drawLine(Offset(x, size.height * .37), Offset(x, size.height * .63), bars);
    }
    final line = Paint()..color = const Color(0xFF69B9FF)..strokeWidth = 3;
    canvas.drawLine(Offset(size.width * .26, size.height / 2),
      Offset(size.width * .74, size.height / 2), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
