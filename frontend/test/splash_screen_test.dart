import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robochess_mobile/presentation/screens/splash_screen.dart';
import 'package:robochess_mobile/presentation/widgets/app_logo.dart';

void main() {
  testWidgets('SplashScreen renders AppLogo and title branding', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SplashScreen(
            duration: Duration(seconds: 10),
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify AppLogo and titles are present
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.text('ROBOCHESS'), findsOneWidget);
    expect(find.text('AUTONOMOUS GRANDMASTER CRAFT'), findsOneWidget);
    expect(find.text('INITIALIZING TOURNAMENT SYSTEM'), findsOneWidget);
  });
}
