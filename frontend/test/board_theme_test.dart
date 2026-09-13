import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robochess_mobile/presentation/providers/board_theme_provider.dart';
import 'package:robochess_mobile/presentation/theme/app_colors.dart';
import 'package:robochess_mobile/presentation/widgets/chess_board_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Board Theme Provider & Chessboard Selection Tests', () {
    test('default board theme is Tournament Wood', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final currentTheme = container.read(boardThemeProvider);

      expect(currentTheme.id, equals('tournament_wood'));
      expect(currentTheme.name, equals('Tournament Wood'));
      expect(currentTheme.lightSquare, equals(kWoodLightSquare));
      expect(currentTheme.darkSquare, equals(kWoodDarkSquare));
      expect(currentTheme.frameColor, equals(kWoodFrame));
    });

    test('provides complete selection of chessboard themes', () {
      expect(kBoardThemes.length, equals(4));
      
      final ids = kBoardThemes.map((t) => t.id).toList();
      expect(ids, contains('tournament_wood'));
      expect(ids, contains('tournament_green'));
      expect(ids, contains('birch_teak'));
      expect(ids, contains('modern_slate'));

      // Check Tournament Green specs
      final greenTheme = kBoardThemes.firstWhere((t) => t.id == 'tournament_green');
      expect(greenTheme.lightSquare, equals(const Color(0xFFEEEED2)));
      expect(greenTheme.darkSquare, equals(const Color(0xFF224D33)));
    });

    test('allows switching board themes dynamically', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(boardThemeProvider.notifier);
      final greenTheme = kBoardThemes.firstWhere((t) => t.id == 'tournament_green');

      notifier.setTheme(greenTheme);

      final updatedTheme = container.read(boardThemeProvider);
      expect(updatedTheme.id, equals('tournament_green'));
      expect(updatedTheme.lightSquare, equals(const Color(0xFFEEEED2)));
      expect(updatedTheme.darkSquare, equals(const Color(0xFF224D33)));
    });

    testWidgets('ChessBoardView renders with wooden board by default', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: ChessBoardView(
                    game: chess.Chess(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChessBoardView), findsOneWidget);
    });
  });
}
