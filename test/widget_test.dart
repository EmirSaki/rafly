import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rafly/main.dart';
import 'package:rafly/providers/student_auth_provider.dart';

void main() {
  testWidgets('App renders role selection page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => StudentAuthProvider(),
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Rafly'), findsOneWidget);
    expect(find.text('Gizlilik Politikası'), findsOneWidget);
    expect(find.text('Hesap Silme'), findsOneWidget);
  });
}
