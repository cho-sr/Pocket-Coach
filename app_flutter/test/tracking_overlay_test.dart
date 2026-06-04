import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach_ui/screens/camera_screen.dart';
import 'package:pocket_coach_ui/screens/live_tracking_screen.dart';
import 'package:pocket_coach_ui/theme/app_theme.dart';
import 'package:pocket_coach_ui/widgets/detection_overlay.dart';

void main() {
  testWidgets('Camera screen includes detection overlay',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPocketCoachTheme(),
        home: CameraScreen(
          onRecordingComplete: (_, __) {},
          trackingBusy: false,
        ),
      ),
    );

    expect(find.byType(DetectionOverlay), findsNothing);
    expect(find.text('Camera Feed Online'), findsOneWidget);
  });

  testWidgets('Live tracking screen includes detection overlay',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPocketCoachTheme(),
        home: const LiveTrackingScreen(),
      ),
    );

    expect(find.byType(DetectionOverlay), findsOneWidget);
    expect(find.text('Player ID #7 Locked'), findsOneWidget);
  });
}
