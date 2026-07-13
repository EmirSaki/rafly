import 'package:flutter/material.dart';
import '../constants/book_categories.dart';
import '../main.dart';

/// Birden fazla kitap kategorisi seçilebilen alan.
///
/// Seçili kategoriler chip olarak gösterilir. Alana dokununca arama yapılabilen
/// bir liste (bottom sheet) açılır ve kategoriler işaretlenerek seçilir.
/// Listede olmayan (ör. ISBN aramasından gelen) kategoriler de korunur.
class CategoryMultiSelect extends StatelessWidget {
  final String label;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const CategoryMultiSelect({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CategoryPickerSheet(initialSelected: selected),
    );

    if (result != null) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          InkWell(
            onTap: () => _openPicker(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBorder),
              ),
              child: selected.isEmpty
                  ? const Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Kategori seçin",
                            style: TextStyle(
                                fontSize: 14, color: kTextSecondary),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: kTextSecondary),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "${selected.length} kategori seçili",
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: kTextPrimary,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down,
                                color: kTextSecondary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: selected.map((cat) {
                            return Chip(
                              label: Text(
                                cat,
                                style: const TextStyle(
                                    fontSize: 12, color: kPrimary),
                              ),
                              backgroundColor:
                                  kPrimary.withValues(alpha: 0.08),
                              side: BorderSide(
                                  color: kPrimary.withValues(alpha: 0.2)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              deleteIcon: const Icon(Icons.close, size: 14),
                              deleteIconColor: kPrimary,
                              onDeleted: () {
                                final updated = List<String>.from(selected)
                                  ..remove(cat);
                                onChanged(updated);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  final List<String> initialSelected;

  const _CategoryPickerSheet({required this.initialSelected});

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  late List<String> _selected;
  String _query = "";

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.initialSelected);
  }

  /// Sabit liste + seçili olan ama listede olmayan (özel) kategoriler.
  List<String> get _allOptions {
    final extras = _selected
        .where((c) => !kBookCategories.contains(c))
        .toList();
    return [...extras, ...kBookCategories];
  }

  List<String> get _filtered {
    if (_query.trim().isEmpty) return _allOptions;
    final q = _query.toLowerCase();
    return _allOptions
        .where((c) => c.toLowerCase().contains(q))
        .toList();
  }

  void _toggle(String category) {
    setState(() {
      if (_selected.contains(category)) {
        _selected.remove(category);
      } else {
        _selected.add(category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final filtered = _filtered;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Kategori Seç",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text("Temizle"),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14, color: kTextPrimary),
                decoration: InputDecoration(
                  hintText: "Kategori ara...",
                  prefixIcon:
                      const Icon(Icons.search, size: 20, color: kTextSecondary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "Kategori bulunamadı",
                        style: TextStyle(color: kTextSecondary),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final category = filtered[index];
                        final checked = _selected.contains(category);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (_) => _toggle(category),
                          title: Text(
                            category,
                            style: const TextStyle(
                                fontSize: 14, color: kTextPrimary),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: kPrimary,
                          dense: true,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(
                      _selected.isEmpty
                          ? "Tamam"
                          : "Onayla (${_selected.length})",
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
