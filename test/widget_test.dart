import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rafly/main.dart';
import 'package:rafly/providers/student_auth_provider.dart';

void main() {
  testWidgets('App renders role selection page', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => StudentAuthProvider(),
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Rafly'), findsOneWidget);
  });
}
