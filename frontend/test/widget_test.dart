import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robochess_mobile/main.dart';

void main() {
  testWidgets('app opens splash screen by default with branding',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RoboChessApp()));
    await tester.pump();
    expect(find.text('ROBOCHESS'), findsOneWidget);
    expect(find.text('AUTONOMOUS GRANDMASTER CRAFT'), findsOneWidget);
  });

  testWidgets('app opens the guest-capable login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: RoboChessApp(initialLocation: '/login'),
    ));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('PLAY LOCALLY WITHOUT INTERNET'), findsOneWidget);
  });

  for (final route in ['/home', '/play', '/connect', '/profile', '/learn']) {
    testWidgets('blocks $route for logged-out users', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: RoboChessApp(initialLocation: route),
      ));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Welcome back'), findsOneWidget);
    });
  }
}
