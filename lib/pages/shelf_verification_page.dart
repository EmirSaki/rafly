import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../main.dart';

enum RowStatus { loading, found, notFound, saving, saved, skipped, error }

class _BookRow {
  final String isbn;
  RowStatus status;
  String? message;

  final TextEditingController titleC = TextEditingController();
  final TextEditingController authorsC = TextEditingController();
  final TextEditingController publisherC = TextEditingController();
  final TextEditingController categoriesC = TextEditingController();
  final TextEditingController pageC = TextEditingController();
  final TextEditingController quantityC = TextEditingController(text: "1");
  int volumeCount = 0;

  _BookRow(this.isbn) : status = RowStatus.loading;

  void dispose() {
    titleC.dispose();
    authorsC.dispose();
    publisherC.dispose();
    categoriesC.dispose();
    pageC.dispose();
    quantityC.dispose();
  }
}

/// Raf modunda toplanan ISBN'leri paralel sorgular, tek tek dolan
/// düzenlenebilir kartlarda gösterir; her kart aktif rafa kaydedilebilir.
class ShelfVerificationPage extends StatefulWidget {
  final String schoolCode;
  final String shelf;
  final List<String> isbns;

  /// Tarama sırasında başlatılan sorguların sonuçları (prefetch).
  /// Her Future, kitap verisini ya da bulunamadıysa null döndürür (hata atmaz).
  final Map<String, Future<Map<String, dynamic>?>>? prefetched;

  const ShelfVerificationPage({
    super.key,
    required this.schoolCode,
    required this.shelf,
    required this.isbns,
    this.prefetched,
  });

  @override
  State<ShelfVerificationPage> createState() => _ShelfVerificationPageState();
}

class _ShelfVerificationPageState extends State<ShelfVerificationPage> {
  late final List<_BookRow> _rows;
  bool _bulkSaving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.isbns.map((isbn) => _BookRow(isbn)).toList();
    // Her satırın sorgusunu paralel başlat (tek tek dolsun diye await yok)
    for (final row in _rows) {
      _lookup(row);
    }
  }

  Future<void> _lookup(_BookRow row) async {
    try {
      // Tararken başlatılan sorgu varsa onu kullan (yeni istek atma),
      // yoksa şimdi sorgula.
      Map<String, dynamic>? data;
      final pf = widget.prefetched?[row.isbn];
      if (pf != null) {
        data = await pf;
      } else {
        try {
          data = await ApiService.fetchBookByIsbn(row.isbn);
        } catch (_) {
          data = null;
        }
      }

      if (!mounted) return;

      if (data == null) {
        setState(() {
          row.status = RowStatus.notFound;
          row.message = "Bulunamadı — bilgileri elle gir";
        });
        return;
      }

      row.titleC.text = data["title"]?.toString() ?? "";
      row.authorsC.text =
          ApiService.normalizeStringList(data["authors"]).join(", ");
      row.publisherC.text = data["publisher"]?.toString() ?? "";
      row.categoriesC.text =
          ApiService.normalizeStringList(data["categories"]).join(", ");
      row.pageC.text = '${data["pageCount"] ?? 0}';
      row.volumeCount = int.tryParse('${data["volumeCount"] ?? 0}') ?? 0;
      setState(() {
        row.status = RowStatus.found;
        row.message = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        row.status = RowStatus.notFound;
        row.message = "Bulunamadı — bilgileri elle gir";
      });
    }
  }

  Map<String, dynamic> _bookData(_BookRow row) {
    final pageCount = int.tryParse(row.pageC.text.trim()) ?? 0;
    return {
      "title": row.titleC.text.trim(),
      "authors": ApiService.normalizeStringList(row.authorsC.text).toList(),
      "publisher": row.publisherC.text.trim(),
      "categories":
          ApiService.normalizeStringList(row.categoriesC.text).toList(),
      "isbn": ApiService.normalizeIsbn(row.isbn),
      "schoolCode": widget.schoolCode,
      "volumeCount": row.volumeCount,
      "quantity": int.tryParse(row.quantityC.text.trim()) ?? 1,
      "pageCount": pageCount,
      "physicalDescription": pageCount > 0 ? "$pageCount sayfa" : "",
      "shelf": widget.shelf,
    };
  }

  /// Tek bir satırı kaydeder. Sessiz (bulk) modda snackbar göstermez.
  Future<bool> _save(_BookRow row, {bool silent = false}) async {
    final title = row.titleC.text.trim();
    final isbn = ApiService.normalizeIsbn(row.isbn);
    final qty = int.tryParse(row.quantityC.text.trim()) ?? 1;

    if (title.isEmpty) {
      setState(() => row.message = "Kitap adı boş olamaz");
      return false;
    }
    if (isbn.length != 10 && isbn.length != 13) {
      setState(() => row.message = "ISBN geçersiz");
      return false;
    }
    if (qty <= 0) {
      setState(() => row.message = "Adet en az 1 olmalı");
      return false;
    }

    setState(() {
      row.status = RowStatus.saving;
      row.message = null;
    });

    try {
      var decoded = await ApiService.saveBook(
        bookData: _bookData(row),
        increaseQuantity: false,
      );

      final alreadyExists = decoded["alreadyExists"] == true ||
          decoded["alreadyExistsInSchool"] == true;

      if (decoded["success"] != true && alreadyExists) {
        // Zaten kayıtlı: raf akışında otomatik adet artır
        decoded = await ApiService.saveBook(
          bookData: _bookData(row),
          increaseQuantity: true,
        );
      }

      if (!mounted) return false;

      if (decoded["success"] == true) {
        setState(() {
          row.status = RowStatus.saved;
          row.message = null;
        });
        if (!silent) _snack("\"$title\" → ${widget.shelf} rafına eklendi");
        return true;
      }

      setState(() {
        row.status = RowStatus.found;
        row.message = decoded["message"]?.toString() ?? "Kaydedilemedi";
      });
      return false;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains("zaten var") ||
          msg.contains("artırılsın") ||
          msg.contains("zaten kayıtlı")) {
        try {
          final inc = await ApiService.saveBook(
            bookData: _bookData(row),
            increaseQuantity: true,
          );
          if (!mounted) return false;
          if (inc["success"] == true) {
            setState(() {
              row.status = RowStatus.saved;
              row.message = "Zaten vardı, adet artırıldı";
            });
            if (!silent) _snack("\"$title\" adedi artırıldı");
            return true;
          }
        } catch (_) {}
      }
      if (!mounted) return false;
      setState(() {
        row.status = RowStatus.found;
        row.message = "Kaydetme hatası";
      });
      return false;
    }
  }

  void _skip(_BookRow row) {
    setState(() {
      row.status = RowStatus.skipped;
      row.message = "Atlandı";
    });
  }

  void _reactivate(_BookRow row) {
    setState(() {
      row.status =
          row.titleC.text.trim().isEmpty ? RowStatus.notFound : RowStatus.found;
      row.message = null;
    });
  }

  Future<void> _saveAll() async {
    setState(() => _bulkSaving = true);
    for (final row in _rows) {
      final editable =
          row.status == RowStatus.found || row.status == RowStatus.notFound;
      if (editable && row.titleC.text.trim().isNotEmpty) {
        await _save(row, silent: true);
      }
    }
    if (!mounted) return;
    setState(() => _bulkSaving = false);
    final saved = _rows.where((r) => r.status == RowStatus.saved).length;
    _snack("$saved kitap ${widget.shelf} rafına kaydedildi");
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  bool get _anyLoading => _rows.any((r) => r.status == RowStatus.loading);

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedCount = _rows.where((r) => r.status == RowStatus.saved).length;
    final pendingCount = _rows
        .where((r) =>
            r.status == RowStatus.found || r.status == RowStatus.notFound)
        .length;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          title: Text("Raf: ${widget.shelf}"),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: kSurface,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  "${_rows.length} kitap • $savedCount kaydedildi"
                  "${_anyLoading ? " • yükleniyor..." : ""}",
                  style: const TextStyle(fontSize: 13, color: kTextSecondary),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) => _buildRowCard(_rows[index]),
                ),
              ),
              _buildBottomBar(pendingCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(int pendingCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _bulkSaving ? null : () => Navigator.pop(context),
              child: const Text("Bitir"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: (_bulkSaving || _anyLoading || pendingCount == 0)
                  ? null
                  : _saveAll,
              child: _bulkSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text("Tümünü Kaydet ($pendingCount)"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowCard(_BookRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: row.status == RowStatus.saved
              ? Colors.green.withValues(alpha: 0.5)
              : kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "ISBN: ${row.isbn}",
                  style: const TextStyle(
                    fontSize: 12,
                    color: kTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _statusChip(row.status),
            ],
          ),
          if (row.status == RowStatus.loading) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text("Sorgulanıyor...",
                    style: TextStyle(fontSize: 13, color: kTextSecondary)),
              ],
            ),
          ] else if (row.status == RowStatus.saved ||
              row.status == RowStatus.skipped) ...[
            const SizedBox(height: 8),
            Text(
              row.titleC.text.trim().isEmpty
                  ? (row.message ?? "")
                  : row.titleC.text.trim(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kTextPrimary,
              ),
            ),
            if (row.message != null) ...[
              const SizedBox(height: 2),
              Text(row.message!,
                  style: const TextStyle(fontSize: 12, color: kTextSecondary)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _reactivate(row),
                child: const Text("Geri Al"),
              ),
            ),
          ] else ...[
            // found / notFound / saving / error -> düzenlenebilir form
            const SizedBox(height: 10),
            _field("Kitap Adı", row.titleC),
            _field("Yazarlar (virgülle)", row.authorsC),
            _field("Yayınevi", row.publisherC),
            _field("Kategoriler (virgülle)", row.categoriesC),
            Row(
              children: [
                Expanded(
                  child: _field("Sayfa", row.pageC,
                      number: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field("Adet", row.quantityC, number: true),
                ),
              ],
            ),
            if (row.message != null) ...[
              const SizedBox(height: 4),
              Text(row.message!,
                  style: const TextStyle(fontSize: 12, color: kDestructive)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: row.status == RowStatus.saving
                        ? null
                        : () => _skip(row),
                    child: const Text("Atla"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: row.status == RowStatus.saving
                        ? null
                        : () => _save(row),
                    child: row.status == RowStatus.saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("Kaydet"),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(RowStatus status) {
    late final String label;
    late final Color color;
    switch (status) {
      case RowStatus.loading:
        label = "Yükleniyor";
        color = kTextSecondary;
        break;
      case RowStatus.found:
        label = "Bulundu";
        color = kPrimary;
        break;
      case RowStatus.notFound:
        label = "Elle Gir";
        color = Colors.orange;
        break;
      case RowStatus.saving:
        label = "Kaydediliyor";
        color = kTextSecondary;
        break;
      case RowStatus.saved:
        label = "Kaydedildi";
        color = Colors.green;
        break;
      case RowStatus.skipped:
        label = "Atlandı";
        color = kTextSecondary;
        break;
      case RowStatus.error:
        label = "Hata";
        color = kDestructive;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters:
                number ? [FilteringTextInputFormatter.digitsOnly] : null,
            textCapitalization:
                number ? TextCapitalization.none : TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: kTextPrimary),
            decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
