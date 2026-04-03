import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_diet/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows rebuilt meal logging experience', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AnKiengApp());
    await tester.pumpAndSettle();

    expect(find.text('Review dashboard'), findsOneWidget);
    expect(find.text('Diet mission'), findsOneWidget);
    expect(find.text('Meal timeline'), findsOneWidget);
    expect(find.text('Log a meal'), findsOneWidget);
  });
}
