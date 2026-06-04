import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach_ui/theme/app_theme.dart';
import 'package:pocket_coach_ui/widgets/detection_overlay.dart';

void main() {
  testWidgets('DetectionOverlay renders bounding boxes in a 16:9 view',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPocketCoachTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 1024,
            height: 576,
            child: DetectionOverlay(),
          ),
        ),
      ),
    );

    final overlayFinder = find.byType(DetectionOverlay);
    final labelFinder = find.text('Player ID #7 Locked');

    expect(overlayFinder, findsOneWidget);
    expect(labelFinder, findsOneWidget);
    expect(
      find.descendant(
        of: overlayFinder,
        matching: find.byType(CustomPaint),
      ),
      findsNWidgets(4),
    );

    final overlayRect = tester.getRect(overlayFinder);
    final labelRect = tester.getRect(labelFinder);

    expect(labelRect.left, greaterThanOrEqualTo(overlayRect.left));
    expect(labelRect.top, greaterThanOrEqualTo(overlayRect.top));
    expect(labelRect.right, lessThanOrEqualTo(overlayRect.right));
    expect(labelRect.bottom, lessThanOrEqualTo(overlayRect.bottom));
  });
}
