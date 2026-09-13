import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/board_theme_provider.dart';
import '../theme/app_colors.dart';
import 'chess_piece_widget.dart';

/// A tap-to-move chessboard.
///
/// Rendering only: the caller owns the [game] and decides what a move means.
/// Set [flipped] to view from Black's side, which the multiplayer screen needs
/// so each player sees their own pieces at the bottom.
class ChessBoardView extends ConsumerWidget {
  final chess.Chess game;
  final bool interactive;
  final bool flipped;
  final String? selectedSquare;
  final Set<String> legalDestinations;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final void Function(String square)? onSquareTap;

  const ChessBoardView({
    super.key,
    required this.game,
    this.interactive = true,
    this.flipped = false,
    this.selectedSquare,
    this.legalDestinations = const {},
    this.lastMoveFrom,
    this.lastMoveTo,
    this.onSquareTap,
  });

  /// Board square for a grid cell, accounting for the viewing side.
  String _squareName(int row, int col) {
    final displayRow = flipped ? 7 - row : row;
    final displayCol = flipped ? 7 - col : col;
    final file = String.fromCharCode('a'.codeUnitAt(0) + displayCol);
    return '$file${8 - displayRow}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardTheme = ref.watch(boardThemeProvider);
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: boardTheme.frameColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: kWoodBrassAccent.withOpacity(0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A2E1B).withOpacity(0.22),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8),
            itemCount: 64,
            itemBuilder: (_, idx) {
              final row = idx ~/ 8;
              final col = idx % 8;
              final squareName = _squareName(row, col);
              final isLight = (row + col) % 2 == 0;
              final piece = game.get(squareName);

              final isSelected = interactive && squareName == selectedSquare;
              final isLegalDest =
                  interactive && legalDestinations.contains(squareName);
              final isLastMove =
                  squareName == lastMoveFrom || squareName == lastMoveTo;

              Color bgColor;
              if (isSelected) {
                bgColor = kPrimaryContainer.withOpacity(0.45);
              } else if (isLastMove) {
                bgColor = kPrimaryContainer.withOpacity(0.22);
              } else {
                bgColor =
                    isLight ? boardTheme.lightSquare : boardTheme.darkSquare;
              }

              return GestureDetector(
                onTap: interactive && onSquareTap != null
                    ? () => onSquareTap!(squareName)
                    : null,
                child: Container(
                  decoration: BoxDecoration(color: bgColor),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isLegalDest && piece == null)
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kPrimary.withOpacity(0.55),
                          ),
                        ),
                      if (isLegalDest && piece != null)
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: kPrimary, width: 3),
                          ),
                        ),
                      if (piece != null)
                        Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: ChessPieceWidget.fromPiece(
                            piece: piece,
                          ),
                        ),
                      if (col == 0)
                        Positioned(
                          top: 2,
                          left: 3,
                          child: Text(
                            squareName.substring(1),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: isLight
                                  ? boardTheme.darkSquare
                                      .withValues(alpha: 0.85)
                                  : boardTheme.lightSquare
                                      .withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      if (row == 7)
                        Positioned(
                          bottom: 2,
                          right: 3,
                          child: Text(
                            squareName.substring(0, 1),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: isLight
                                  ? boardTheme.darkSquare
                                      .withValues(alpha: 0.85)
                                  : boardTheme.lightSquare
                                      .withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
