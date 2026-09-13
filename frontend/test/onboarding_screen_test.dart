import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robochess_mobile/presentation/screens/onboarding_screen.dart';

void main() {
  testWidgets('renders OnboardingScreen with title and action buttons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScreen(),
      ),
    );
    await tester.pump();

    // Verify initial slide content
    expect(find.text('Autonomous Robotic Chess'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('PHYSICAL ROBOTICS'), findsOneWidget);

    // Tap Continue to advance to slide 2
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    // Verify slide 2 content
    expect(find.text('Dual Link & Telemetry'), findsOneWidget);
    expect(find.text('SMART CONNECT'), findsOneWidget);

    // Tap Continue to advance to slide 3
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    // Verify slide 3 content and completion CTA
    expect(find.text('Tactics, Openings & AI'), findsOneWidget);
    expect(find.text('GET STARTED'), findsOneWidget);
  });
}
