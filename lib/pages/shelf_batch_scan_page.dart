import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'shelf_verification_page.dart';

/// Raf modu çoklu tarama: bir oturumda 6 ISBN'e kadar toplar,
/// sonra doğrulama sayfasında paralel sorgulayıp aktif rafa kaydeder.
class ShelfBatchScanPage extends StatefulWidget {
  final String schoolCode;

  const ShelfBatchScanPage({
    super.key,
    required this.schoolCode,
  });

  @override
  State<ShelfBatchScanPage> createState() => _ShelfBatchScanPageState();
}

class _ShelfBatchScanPageState extends State<ShelfBatchScanPage> {
  static const int maxIsbns = 30;

  // ISBN barkodları EAN-13'tür. Formatı EAN-13'e kilitlemek taramayı
  // hızlandırır ve QR/fiyat barkodu gibi gürültüyü eler. Tek tek onaylı
  // akış: bir okuma alınır, onaylanana kadar kamera durur.
  final MobileScannerController scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 200,
    formats: const [BarcodeFormat.ean13],
  );
  final List<String> _isbns = [];
  // Yeni okunan ama henüz "Sıradaki" ile onaylanmamış ISBN.
  // Doluyken kamera durur; onaylanınca listeye eklenir.
  String? _pendingIsbn;
  // Tararken başlatılan sorgular: her ISBN okununca sorgusu hemen atılır,
  // sonucu (veya bulunamadıysa null) burada bekler. Doğrulama sayfasına
  // aktarılır ki aynı sorgu ikinci kez atılmasın.
  final Map<String, Future<Map<String, dynamic>?>> _prefetch = {};
  String? _shelf;
  String statusMessage = "Bir kitabın barkodunu okut";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptShelf(isInitial: true);
    });
  }

  String _normalizeIsbn(String value) {
    return value.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase().trim();
  }

  bool _isValidIsbn(String value) {
    final n = _normalizeIsbn(value);
    // 13 haneli barkodlarda sadece kitap (Bookland) ön eki 978/979 kabul
    // edilir — kapaktaki fiyat/ürün EAN'lerini elemek için.
    if (n.length == 13) return n.startsWith('978') || n.startsWith('979');
    return n.length == 10;
  }

  // ISBN okunur okunmaz sorgusunu başlatır. Hata atmaz: bulunamazsa
  // null'a çözülür; böylece güvenle saklanıp sonra await edilebilir.
  Future<Map<String, dynamic>?> _startLookup(String isbn) {
    return ApiService.fetchBookByIsbn(isbn)
        .then<Map<String, dynamic>?>((data) => data)
        .catchError((_) => null);
  }

  Future<void> _promptShelf({bool isInitial = false}) async {
    final controller = TextEditingController(text: _shelf ?? "");
    try {
      await scannerController.stop();
    } catch (_) {}

    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: !isInitial,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isInitial ? "Raf Adı" : "Rafı Değiştir"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isInitial
                    ? "Bu oturumda taranan kitaplar bu rafa kaydedilecek."
                    : "Bundan sonra taranan kitaplar yeni rafa kaydedilecek.",
                style: const TextStyle(fontSize: 13, color: kTextSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: "Örn: A-3 / Roman Rafı",
                ),
                onSubmitted: (v) =>
                    Navigator.of(dialogContext).pop(v.trim()),
              ),
            ],
          ),
          actions: [
            if (!isInitial)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text("Vazgeç"),
              ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text("Onayla"),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (result == null || result.isEmpty) {
      if (isInitial && (_shelf == null || _shelf!.isEmpty)) {
        Navigator.of(context).pop();
        return;
      }
      await _restartScanner();
      return;
    }

    setState(() => _shelf = result);
    await _restartScanner();
  }

  Future<void> _restartScanner() async {
    if (!mounted) return;
    setState(() {
      statusMessage = _isbns.isEmpty
          ? "Bir kitabın barkodunu okut"
          : "${_isbns.length} onaylandı — sıradaki kitabı okut";
    });
    try {
      await scannerController.start();
    } catch (_) {}
  }

  void _onDetect(BarcodeCapture capture) {
    // Onay bekleyen bir okuma varsa ya da liste doluysa yeni okuma alma
    if (_pendingIsbn != null || _isbns.length >= maxIsbns) return;

    // Tek tek onaylı akış: karedeki ilk geçerli ISBN'i al.
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue ?? barcode.displayValue;
      if (code == null || code.trim().isEmpty) continue;
      final isbn = _normalizeIsbn(code);
      if (!_isValidIsbn(isbn)) continue;

      // Aynı kamera sekansında zaten okunmuşsa tekrar ekleme, uyar
      if (_isbns.contains(isbn)) {
        HapticFeedback.lightImpact();
        setState(() => statusMessage = "Bu kitap zaten okundu: $isbn");
        return;
      }

      _pendingIsbn = isbn;
      // Okunur okunmaz sorgusunu arka planda başlat (onayı beklemez)
      _prefetch[isbn] = _startLookup(isbn);
      HapticFeedback.mediumImpact();
      scannerController.stop().catchError((_) {});
      setState(() {
        statusMessage = "Okundu: $isbn — Sıradaki ile onayla";
      });
      return;
    }
  }

  // "Sıradaki": bekleyen okumayı onaylar, listeye ekler, kamerayı devam ettirir
  Future<void> _confirmPending() async {
    final isbn = _pendingIsbn;
    if (isbn == null) return;
    setState(() {
      _isbns.add(isbn);
      _pendingIsbn = null;
    });
    await _restartScanner();
  }

  // Yanlış/istenmeyen okumayı at, tekrar okumaya dön
  Future<void> _discardPending() async {
    final isbn = _pendingIsbn;
    if (isbn == null) return;
    setState(() {
      _prefetch.remove(isbn);
      _pendingIsbn = null;
    });
    await _restartScanner();
  }

  void _removeIsbn(String isbn) {
    setState(() {
      _isbns.remove(isbn);
      _prefetch.remove(isbn);
    });
  }

  Future<void> _proceed() async {
    if (_shelf == null) return;

    // Onaylanmamış bekleyen okuma varsa onu da dahil et
    if (_pendingIsbn != null) {
      _isbns.add(_pendingIsbn!);
      _pendingIsbn = null;
    }
    if (_isbns.isEmpty) return;

    try {
      await scannerController.stop();
    } catch (_) {}

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShelfVerificationPage(
          schoolCode: widget.schoolCode,
          shelf: _shelf!,
          isbns: List<String>.from(_isbns),
          prefetched: Map<String, Future<Map<String, dynamic>?>>.from(_prefetch),
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _isbns.clear();
      _prefetch.clear();
    });
    await _restartScanner();
  }

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _shelf?.isNotEmpty == true ? "Raf: $_shelf" : "Raf Olarak Ekle",
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "change_shelf") _promptShelf();
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: "change_shelf",
                child: Row(
                  children: [
                    Icon(Icons.shelves, size: 18, color: kTextPrimary),
                    SizedBox(width: 8),
                    Text("Rafı Değiştir"),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: _onDetect,
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
                const Center(
                  child: IgnorePointer(
                    child: Icon(Icons.qr_code_scanner,
                        size: 120, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final hasPending = _pendingIsbn != null;
    // Sistem navigasyon çubuğu (gesture/tuş) kadar alt boşluk bırak ki
    // butonlar navigasyon tuşlarıyla çakışmasın.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Onaylanan: ${_isbns.length}/$maxIsbns",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // Bekleyen okuma kartı (onay bekliyor)
          if (hasPending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2, size: 20, color: kPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Okundu: $_pendingIsbn",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "Bu okumayı at, tekrar oku",
                    icon: const Icon(Icons.close, size: 20),
                    color: kTextSecondary,
                    onPressed: _discardPending,
                  ),
                ],
              ),
            )
          else if (_isbns.isEmpty)
            const Text(
              "Bir kitabın barkodunu okut, sonra Sıradaki ile onayla.",
              style: TextStyle(fontSize: 12, color: kTextSecondary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _isbns
                  .map(
                    (isbn) => Chip(
                      label: Text(isbn, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => _removeIsbn(isbn),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: (_isbns.isEmpty && !hasPending) ? null : _proceed,
                    child: Text("Bitti (${_isbns.length})"),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: hasPending ? _confirmPending : null,
                    child: const Text("Sıradaki"),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
