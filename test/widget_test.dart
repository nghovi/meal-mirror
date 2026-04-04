import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_diet/pages/auth_page.dart';
import 'package:my_diet/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows auth page content', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: AuthPage(authService: AuthService.instance),
      ),
    );
    await tester.pump();

    expect(find.text('Meal Mirror'), findsOneWidget);
    expect(find.text('Sign in to your Meal Mirror account'), findsOneWidget);
    expect(
      find.text(
        'Your meals, drinks, and Mira chat will live on the server, not only on this phone.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
  });
}
