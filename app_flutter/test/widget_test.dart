import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_coach_ui/main.dart';

void main() {
  testWidgets('Pocket Coach home renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PocketCoachApp());

    expect(find.text('Pocket Coach'), findsOneWidget);
    expect(find.text('Start Tracking'), findsOneWidget);
  });
}
