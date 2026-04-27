import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../widgets/animated_profile_avatar.dart';

// ── Colour tokens ────────────────────────────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHigh = Color(0xFF2C2A27);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kPrimaryContainer = Color(0xFF68B631);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutline = Color(0xFF8A9480);
const kOutlineVariant = Color(0xFF414939);
const kError = Color(0xFFFFB4AB);

// Piece symbols using unicode chess characters
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

// Checkmate position based on move history ending with Re8#
const _finalBoard = [
  ['r', null, null, null, 'R', null, null, 'k'], 
  ['p', 'p', 'p', 'R', null, null, null, 'p'], // White Rook on d7, Black pawns
  [null, null, 'p', null, null, 'p', null, null], // Black pawns on c6, f6 (g7->f6)
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  [null, null, 'P', null, null, 'P', 'P', null],
  ['P', 'P', null, null, null, null, null, 'P'], 
  [null, null, null, null, null, null, 'K', null],
];

// Highlighted squares from the last move Re8# (e1 to e8)
const _highlightSquares = {
  '0,4': 0.3, // e8
  '7,4': 0.1, // e1
};

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            const Icon(Icons.settings_remote, color: kPrimary),
            const SizedBox(width: 10),
            Text('ROBOCHESS',
                style: GoogleFonts.spaceGrotesk(
                    color: kPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 2)),
          ],
        ),
        actions: [
          const AnimatedProfileAvatar(size: 38),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        child: Column(
          children: [
            // ── Board + Graph (left col) ──────────────────────────────────
            _BoardSection(),
            const SizedBox(height: 16),
            _MomentumGraph(),
            const SizedBox(height: 16),
            // ── Move History ──────────────────────────────────────────────
            _MoveHistory(),
            const SizedBox(height: 16),
            // ── AI Insight ────────────────────────────────────────────────
            _AIInsightPanel(),
            const SizedBox(height: 16),
            // ── Action Buttons ────────────────────────────────────────────
            _ActionButtons(),
          ],
        ),
      ),
      // Floating dashboard button
      floatingActionButton: FloatingActionButton(
        backgroundColor: kSurfaceContHighest,
        foregroundColor: kOnSurface,
        onPressed: () {},
        child: const Icon(Icons.dashboard),
      ),
    );
  }
}

// ── Board Section ────────────────────────────────────────────────────────────
class _BoardSection extends StatelessWidget {
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: kPrimary, size: 20),
              const SizedBox(width: 8),
              Text('FINAL POSITION',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kSurfaceContHighest,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimary,
                        boxShadow: [
                          BoxShadow(
                              color: kPrimary.withOpacity(0.5), blurRadius: 4)
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('LIVE EVAL: +1.4',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                // Chess grid
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: kSurfaceContHighest,
                  ),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                    ),
                    itemCount: 64,
                    itemBuilder: (context, index) {
                      final row = index ~/ 8;
                      final col = index % 8;
                      final isLight = (row + col) % 2 == 0;
                      final piece = _finalBoard[row][col];
                      final highlightKey = '$row,$col';
                      final highlightOpacity = _highlightSquares[highlightKey] ?? 0.0;
                      return Container(
                        decoration: BoxDecoration(
                          color: highlightOpacity > 0
                              ? kPrimary.withOpacity(highlightOpacity)
                              : isLight
                                  ? kSurfaceContHigh
                                  : kSurfaceContLow,
                          boxShadow: highlightOpacity > 0
                              ? [
                                  BoxShadow(
                                      color: kPrimary.withOpacity(highlightOpacity * 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 1)
                                ]
                              : null,
                        ),
                        child: Stack(
                          children: [
                            if (piece != null)
                              Center(
                                child: Text(
                                  _pieceSymbol(piece),
                                  style: TextStyle(
                                    fontSize: 24,
                                    color: _pieceColor(piece),
                                    shadows: [
                                      Shadow(
                                        color: _pieceColor(piece).withOpacity(0.4),
                                        blurRadius: 8,
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            // Row notation (1-8)
                            if (col == 0)
                              Positioned(
                                top: 2,
                                left: 4,
                                child: Text(
                                  '${8 - row}',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: isLight ? kOnSurfaceVariant : kOutlineVariant,
                                  ),
                                ),
                              ),
                            // Col notation (a-h)
                            if (row == 7)
                              Positioned(
                                bottom: 2,
                                right: 4,
                                child: Text(
                                  String.fromCharCode('a'.codeUnitAt(0) + col),
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: isLight ? kOnSurfaceVariant : kOutlineVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Evaluation bar on left
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          flex: 40,
                          child: Container(color: kOnSurface),
                        ),
                        Expanded(
                          flex: 60,
                          child: Container(color: kBackground),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Momentum Graph ───────────────────────────────────────────────────────────
class _MomentumGraph extends StatelessWidget {
  // bar heights as percentages from the HTML
  final _data = const <double>[
    30.0,
    35.0,
    45.0,
    60.0,
    55.0,
    40.0,
    20.0,
    30.0,
    75.0,
    85.0,
    80.0
  ];
  final _colors = const [
    kSurfaceContHighest,
    kSurfaceContHighest,
    kSurfaceContHighest,
    kPrimary,
    kSurfaceContHighest,
    kSurfaceContHighest,
    kError,
    kSurfaceContHighest,
    kPrimaryContainer,
    kPrimaryContainer,
    kSurfaceContHighest,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MOMENTUM ANALYSIS',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kOutline,
                  letterSpacing: 2)),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                backgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 50,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: v == 50
                        ? kPrimary.withOpacity(0.2)
                        : kOutlineVariant.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: const FlTitlesData(show: false),
                barGroups: List.generate(
                  _data.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: _data[i],
                        color: _colors[i].withOpacity(0.7),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['Opening', 'Midgame', 'Endgame']
                .map((label) => Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kOutline,
                        letterSpacing: 2)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Move History ─────────────────────────────────────────────────────────────
class _MoveHistory extends StatelessWidget {
  final _moves = const [
    _Move('24', 'Rd7+', MoveTag.brilliant, 'Kh8', MoveTag.best, false),
    _Move('25', 'Qxf6', MoveTag.great, 'gxf6?', MoveTag.mistake, true),
    _Move('26', 'Re8#', MoveTag.book, 'Game Over', MoveTag.none, false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Move History',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: kOnSurface)),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.download,
                      color: kOnSurfaceVariant, size: 20),
                ),
              ],
            ),
          ),
          const Divider(color: kOutlineVariant, height: 1, thickness: 0.2),
          ..._moves.map((m) => _MoveRow(move: m)),
        ],
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  final _Move move;
  const _MoveRow({required this.move});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: move.isHighlighted
            ? kPrimary.withOpacity(0.05)
            : Colors.transparent,
        border: move.isHighlighted
            ? const Border(left: BorderSide(color: kPrimary, width: 2))
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${move.number}.',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: kOutline,
                    fontFeatures: [const FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: Row(
              children: [
                Text(move.white,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: move.isHighlighted ? kPrimary : kOnSurface)),
                const SizedBox(width: 6),
                if (move.whiteTag != MoveTag.none) _TagChip(tag: move.whiteTag),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text(move.black,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: move.blackTag == MoveTag.mistake
                            ? kError
                            : move.black == 'Game Over'
                                ? kOutline
                                : kOnSurface,
                        fontStyle: move.black == 'Game Over'
                            ? FontStyle.italic
                            : FontStyle.normal)),
                const SizedBox(width: 6),
                if (move.blackTag != MoveTag.none) _TagChip(tag: move.blackTag),
              ],
            ),
          ),
          move.isHighlighted
              ? const Icon(Icons.play_circle, color: kPrimary, size: 18)
              : const Icon(Icons.chevron_right,
                  color: kOnSurfaceVariant, size: 18),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final MoveTag tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (tag) {
      case MoveTag.brilliant:
        bg = kPrimary.withOpacity(0.2);
        fg = kPrimary;
        label = 'Brilliant';
        break;
      case MoveTag.great:
        bg = kPrimary.withOpacity(0.2);
        fg = kPrimary;
        label = 'Great';
        break;
      case MoveTag.best:
        bg = kSurfaceContHighest;
        fg = kOutline;
        label = 'Best';
        break;
      case MoveTag.mistake:
        bg = kError.withOpacity(0.2);
        fg = kError;
        label = 'Mistake';
        break;
      case MoveTag.book:
        bg = kSecondary.withOpacity(0.1);
        fg = kSecondary;
        label = 'Book';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 1)),
    );
  }
}

enum MoveTag { brilliant, great, best, mistake, book, none }

class _Move {
  final String number, white, black;
  final MoveTag whiteTag, blackTag;
  final bool isHighlighted;
  const _Move(this.number, this.white, this.whiteTag, this.black, this.blackTag,
      this.isHighlighted);
}

// ── AI Insight Panel ─────────────────────────────────────────────────────────
class _AIInsightPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withOpacity(0.1)),
      ),
      child: Stack(
        children: [
          // Left green bar
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: const BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.psychology, color: kPrimary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ROBO-INSIGHT V4.2',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                              letterSpacing: 2)),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: kOnSurfaceVariant,
                              height: 1.6),
                          children: [
                            const TextSpan(text: 'The AI suggests '),
                            TextSpan(
                                text: 'e4',
                                style: GoogleFonts.inter(
                                    color: kPrimary,
                                    fontWeight: FontWeight.w700)),
                            const TextSpan(text: ' instead of '),
                            TextSpan(
                                text: 'd4',
                                style: GoogleFonts.inter(
                                    color: kError,
                                    fontWeight: FontWeight.w700)),
                            const TextSpan(
                                text:
                                    ' to control the center more effectively. Transitioning to an open game structure would increase your positional advantage by '),
                            TextSpan(
                                text: '+0.8',
                                style: GoogleFonts.inter(
                                    color: kPrimary,
                                    fontWeight: FontWeight.w700)),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('SIMULATE VARIATION',
                              style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: kPrimary,
                                  letterSpacing: 2)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward,
                              color: kPrimary, size: 14),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action Buttons ───────────────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              backgroundColor: kSurfaceContLow,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.share, color: kOnSurface, size: 16),
            label: Text('EXPORT PGN',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface,
                    letterSpacing: 2)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: kOnPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              shadowColor: kPrimary.withOpacity(0.3),
              elevation: 8,
            ),
            icon: const Icon(Icons.replay, size: 16),
            label: Text('REMATCH',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
          ),
        ),
      ],
    );
  }
}
