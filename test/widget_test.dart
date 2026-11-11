import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rafly/main.dart';
import 'package:rafly/pages/home_page.dart';
import 'package:rafly/providers/student_auth_provider.dart';
import 'package:rafly/student/student_profile_screen.dart';
import 'package:rafly/student/student_main_shell.dart';

void main() {
  testWidgets('role selection opens the student login and policy menu', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => StudentAuthProvider(),
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Giriş türünüzü seçin'), findsOneWidget);
    final version = find.text('Rafly v1.0.2');
    await tester.ensureVisible(version);
    await tester.tap(version);
    await tester.pumpAndSettle();
    expect(find.text('Gizlilik Politikası'), findsOneWidget);
    expect(find.text('Hesap Silme'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final studentRole = find.text('Öğrenci/Öğretmen Girişi');
    await tester.ensureVisible(studentRole);
    await tester.tap(studentRole);
    await tester.pumpAndSettle();
    expect(find.text('Öğrenci Paneli'), findsOneWidget);
    expect(find.text('Okul Seviyesi'), findsOneWidget);
  });

  testWidgets('profile edit shows Other actions and delete confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => StudentAuthProvider(),
        child: const MaterialApp(home: StudentProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profilini Düzenle'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta adresinizi girin'), findsOneWidget);
    await tester.ensureVisible(find.text('Diğer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diğer'));
    await tester.pumpAndSettle();
    expect(find.text('Bildirim Tercihleri'), findsOneWidget);
    expect(find.text('Gizlilik ve Güvenlik'), findsOneWidget);
    expect(find.text('Yardım ve Destek'), findsOneWidget);
    expect(find.text('Hesabı Sil'), findsOneWidget);

    await tester.ensureVisible(find.text('Hesabı Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hesabı Sil'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bu işlem geri alınamaz.'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
  });

  testWidgets('staff home opens add-book methods and reservation menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: HomePage(
          schoolCode: '123456',
          schoolName: 'Deneme Okulu',
          userName: 'Test',
          userSurname: 'Kullanıcı',
          userRole: 'teacher',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Kitap Ekleme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitap Ekleme'));
    await tester.pumpAndSettle();
    expect(find.text('Barkod Okutma'), findsOneWidget);
    expect(find.text('Manuel Ekleme'), findsOneWidget);
    await tester.tap(find.text('Manuel Ekleme'));
    await tester.pumpAndSettle();
    expect(find.text('ISBN ile Ara'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezervasyonlar'));
    await tester.pumpAndSettle();
    expect(find.text('Kitap Ver'), findsOneWidget);
    expect(find.text('İade Al'), findsOneWidget);
  });

  testWidgets(
    'student tabs keep bottom navigation on books, history and profile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => StudentAuthProvider(),
          child: const MaterialApp(home: StudentMainShell()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kitaplar'));
      await tester.pumpAndSettle();
      expect(find.text('Kitap Listesi'), findsOneWidget);
      expect(find.byIcon(Icons.library_add_rounded), findsNothing);
      expect(find.text('Anasayfa'), findsOneWidget);
      await tester.tap(find.text('Geçmiş'));
      await tester.pumpAndSettle();
      expect(find.text('Rezervasyon Geçmişi'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Profilini Düzenle'), findsOneWidget);
      expect(find.text('Kitaplar'), findsOneWidget);
    },
  );
}
