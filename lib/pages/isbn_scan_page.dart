import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';

class IsbnScanPage extends StatefulWidget {
  const IsbnScanPage({super.key});

  @override
  State<IsbnScanPage> createState() => _IsbnScanPageState();
}

class _IsbnScanPageState extends State<IsbnScanPage> {
  final MobileScannerController scannerController = MobileScannerController();

  bool isDone = false;
  String statusMessage = "ISBN barkodunu okut";

  bool _isValidIsbn(String value) {
    final normalized = ApiService.normalizeIsbn(value);
    return normalized.length == 10 || normalized.length == 13;
  }

  Future<void> _handleCode(String rawCode) async {
    if (isDone) return;

    final isbn = ApiService.normalizeIsbn(rawCode);

    if (!_isValidIsbn(isbn)) {
      setState(() => statusMessage = "Bu barkod ISBN gibi durmuyor");
      return;
    }

    setState(() {
      isDone = true;
      statusMessage = "ISBN okundu: $isbn";
    });

    await scannerController.stop();
    if (!mounted) return;
    Navigator.of(context).pop(isbn);
  }

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ISBN Tara")),
      body: Stack(
        children: [
          MobileScanner(
            controller: scannerController,
            onDetect: (capture) async {
              if (isDone) return;
              for (final barcode in capture.barcodes) {
                final code = barcode.displayValue ?? barcode.rawValue;
                if (code != null && code.trim().isNotEmpty) {
                  await _handleCode(code);
                  break;
                }
              }
            },
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
              child: Icon(
                Icons.qr_code_scanner,
                size: 120,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
