import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rafly/widgets/category_multi_select.dart';
import 'package:rafly/constants/book_categories.dart';

void main() {
  testWidgets('boşken placeholder gösterir ve seçim yapılabilir',
      (WidgetTester tester) async {
    List<String> selected = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CategoryMultiSelect(
                label: "Kategoriler",
                selected: selected,
                onChanged: (list) => setState(() => selected = list),
              );
            },
          ),
        ),
      ),
    );

    // Başlangıçta seçim yok.
    expect(find.text('Kategori seçin'), findsOneWidget);

    // Alana dokun → seçim listesi (bottom sheet) açılır.
    await tester.tap(find.text('Kategori seçin'));
    await tester.pumpAndSettle();

    expect(find.text('Kategori Seç'), findsOneWidget);

    // Arama ile filtreleyip işaretle (küçük test ekranında kaydırma gerekmesin).
    await tester.enterText(find.byType(TextField), 'Roman');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Roman'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Tarih');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Tarih'));
    await tester.pump();

    // Onayla.
    await tester.tap(find.textContaining('Onayla'));
    await tester.pumpAndSettle();

    // İki kategori seçili olmalı.
    expect(selected, containsAll(<String>['Roman', 'Tarih']));
    expect(find.text('2 kategori seçili'), findsOneWidget);
  });

  testWidgets('mevcut seçimler chip olarak görünür ve silinebilir',
      (WidgetTester tester) async {
    List<String> selected = ['Roman', 'Şiir'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CategoryMultiSelect(
                label: "Kategoriler",
                selected: selected,
                onChanged: (list) => setState(() => selected = list),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('2 kategori seçili'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Roman'), findsOneWidget);

    // Chip'teki sil ikonuna bas.
    await tester.tap(find.descendant(
      of: find.widgetWithText(Chip, 'Roman'),
      matching: find.byIcon(Icons.close),
    ));
    await tester.pumpAndSettle();

    expect(selected, equals(<String>['Şiir']));
  });

  test('sabit kategori listesi beklenen kategorileri içerir', () {
    expect(kBookCategories, contains('Deneme'));
    expect(kBookCategories, contains('Tarihi Roman'));
    expect(kBookCategories.length, 44);
  });
}
