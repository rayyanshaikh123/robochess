import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';

// ── Colour tokens ──────────────────────────────────────
const _kSurfaceContLow = Color(0xFF1D1B19);
const _kSurfaceContHigh = Color(0xFF2C2A27);
const _kSurfaceContHighest = Color(0xFF373431);
const _kPrimary = Color(0xFF8ADB52);
const _kSecondary = Color(0xFFA2E7FF);

const _pieceSymbols = {
  'p': '♙',
  'n': '♘',
  'b': '♗',
  'r': '♖',
  'q': '♕',
  'k': '♔',
};

/// A tap-to-move chessboard.
///
/// Rendering only: the caller owns the [game] and decides what a move means.
/// Set [flipped] to view from Black's side, which the multiplayer screen needs
/// so each player sees their own pieces at the bottom.
class ChessBoardView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: _kSurfaceContHighest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: _kPrimary.withOpacity(0.05),
                blurRadius: 40,
                spreadRadius: 10)
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
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
              bgColor = _kPrimary.withOpacity(0.35);
            } else if (isLastMove) {
              bgColor = _kPrimary.withOpacity(0.15);
            } else {
              bgColor = isLight ? _kSurfaceContHigh : _kSurfaceContLow;
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
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kPrimary.withOpacity(0.4),
                        ),
                      ),
                    if (isLegalDest && piece != null)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _kPrimary.withOpacity(0.6), width: 3),
                        ),
                      ),
                    if (piece != null)
                      Text(
                        _pieceSymbols[piece.type.toString().toLowerCase()] ?? '',
                        style: TextStyle(
                          fontSize: 24,
                          color: piece.color == chess.Color.WHITE
                              ? _kPrimary
                              : _kSecondary,
                          shadows: [
                            Shadow(
                              color: (piece.color == chess.Color.WHITE
                                      ? _kPrimary
                                      : _kSecondary)
                                  .withOpacity(0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    if (col == 0)
                      Positioned(
                        top: 1,
                        left: 2,
                        child: Text(squareName.substring(1),
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: isLight
                                    ? _kSurfaceContLow
                                    : _kSurfaceContHigh)),
                      ),
                    if (row == 7)
                      Positioned(
                        bottom: 1,
                        right: 2,
                        child: Text(squareName.substring(0, 1),
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: isLight
                                    ? _kSurfaceContLow
                                    : _kSurfaceContHigh)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
