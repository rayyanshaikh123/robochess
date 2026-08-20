import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robochess_mobile/main.dart';

void main() {
  testWidgets('app opens the guest-capable login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RoboChessApp()));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('PLAY LOCALLY WITHOUT INTERNET'), findsOneWidget);
  });
}
