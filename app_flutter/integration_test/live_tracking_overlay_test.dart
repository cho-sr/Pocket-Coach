import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_coach_ui/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Start Tracking executes model without opening live camera',
      (WidgetTester tester) async {
    await app.main();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Start Tracking'), findsOneWidget);

    await tester.tap(find.text('Start Tracking'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Pocket Coach'), findsOneWidget);
    expect(find.text('Live Tracking'), findsNothing);
  });
}
