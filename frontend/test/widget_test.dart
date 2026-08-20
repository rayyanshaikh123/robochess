import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robochess_mobile/main.dart';

void main() {
  testWidgets('RoboChess app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RoboChessApp()));
    await tester.pumpAndSettle();
    expect(find.byType(RoboChessApp), findsOneWidget);
  });
}
