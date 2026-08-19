import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Colour tokens ──────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurface = Color(0xFF151311);
const kSurfaceContainer = Color(0xFF211F1D);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHigh = Color(0xFF2C2A27);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kPrimaryContainer = Color(0xFF68B631);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);

// ── Pieces ─────────────────────────────────────────────
const _whitePieces = {
  'K': '♔',
  'Q': '♕',
  'R': '♖',
  'B': '♗',
  'N': '♘',
  'P': '♙',
};
const _blackPieces = {
  'K': '♔',
  'Q': '♕',
  'R': '♖',
  'B': '♗',
  'N': '♘',
  'P': '♙',
};

// ── Initial Board ──────────────────────────────────────
const _initialBoard = [
  ['r','n','b','q','k','b','n','r'],
  ['p','p','p','p','p','p','p','p'],
  [null,null,null,null,null,null,null,null],
  [null,null,null,null,null,null,null,null],
  [null,null,null,null,null,null,null,null],
  [null,null,null,null,null,null,null,null],
  ['P','P','P','P','P','P','P','P'],
  ['R','N','B','Q','K','B','N','R'],
];

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Text(
                "ROBOCHESS",
                style: GoogleFonts.spaceGrotesk(
                  color: kPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 30),
              const _LiveBoardCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Live Board (STATIC) ─────────────────────────────────
class _LiveBoardCard extends StatelessWidget {
  const _LiveBoardCard();

  String _pieceSymbol(String? piece) {
    if (piece == null) return '';
    final isWhite = piece == piece.toUpperCase();
    final key = piece.toUpperCase();
    return isWhite ? (_whitePieces[key] ?? '') : (_blackPieces[key] ?? '');
  }

  Color _pieceColor(String? piece) {
    if (piece == null) return Colors.transparent;
    return piece == piece.toUpperCase() ? kPrimary : kSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            "Static Board Preview",
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kOnSurface,
            ),
          ),
          const SizedBox(height: 20),

          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: kSurfaceContHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(6),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 64,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                ),
                itemBuilder: (context, index) {
                  final row = index ~/ 8;
                  final col = index % 8;
                  final isLight = (row + col) % 2 == 0;
                  final piece = _initialBoard[row][col];

                  return Container(
                    color: isLight
                        ? kPrimary.withOpacity(0.15)
                        : kSurfaceContHighest,
                    child: Center(
                      child: piece != null
                          ? Text(
                              _pieceSymbol(piece),
                              style: TextStyle(
                                fontSize: 26,
                                color: _pieceColor(piece),
                              ),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}