import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../widgets/animated_profile_avatar.dart';

// ── Colour tokens (from Stitch design) ──────────────────────────────────────
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

// Piece symbols using unicode chess characters (same style for both sides)
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

// Initial board state — null = empty
const _initialBoard = [
  ['r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'],
  ['p', 'p', 'p', 'p', 'p', 'p', 'p', 'p'],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  ['P', 'P', 'P', 'P', 'P', 'P', 'P', 'P'],
  ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'],
];

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Top App Bar ─────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: kBackground,
              surfaceTintColor: Colors.transparent,
              shadowColor: kPrimary.withOpacity(0.06),
              elevation: 4,
              titleSpacing: 24,
              title: Row(
                children: [
                  const Icon(Icons.settings_remote, color: kPrimary),
                  const SizedBox(width: 10),
                  Text(
                    'ROBOCHESS',
                    style: GoogleFonts.spaceGrotesk(
                      color: kPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              actions: [
                // IoT Sync Indicator
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kSurfaceContHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: kPrimary.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      _PulsingDot(color: kSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'SYNCING',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: kSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Avatar
                const AnimatedProfileAvatar(size: 36),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Status Bar ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: kSurfaceContLow,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border(left: BorderSide(color: kPrimary, width: 4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: kPrimary, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'RoboChess Board: Connected',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: kOnSurface,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Latency: 14ms',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Hero: Live Board + Play vs AI ───────────────────────
                  LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    return isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 7, child: _LiveBoardCard()),
                              const SizedBox(width: 16),
                              Expanded(flex: 5, child: _ActionColumn()),
                            ],
                          )
                        : Column(
                            children: [
                              _LiveBoardCard(),
                              const SizedBox(height: 16),
                              _ActionColumn(),
                            ],
                          );
                  }),
                  const SizedBox(height: 32),

                  // ── Tactical Feed ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Tactical Feed',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface,
                        ),
                      ),
                      Text(
                        'VIEW ALL',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TacticalFeed(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live Board Card ──────────────────────────────────────────────────────────
class _LiveBoardCard extends StatelessWidget {
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live Session',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface)),
                  const SizedBox(height: 4),
                  Text('Mirroring physical board state',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: kOnSurfaceVariant)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kSurfaceContHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('MOVE 24',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Chessboard preview grid
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: kSurfaceContHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kOutlineVariant.withOpacity(0.1)),
              ),
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 1,
                ),
                itemCount: 64,
                itemBuilder: (context, index) {
                  final row = index ~/ 8;
                  final col = index % 8;
                  final isLight = (row + col) % 2 == 0;
                  final piece = _initialBoard[row][col];
                  return Container(
                    decoration: BoxDecoration(
                      color: isLight
                          ? kPrimary.withOpacity(0.15)
                          : kSurfaceContHighest,
                      borderRadius: BorderRadius.circular(1),
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
          ),
        ],
      ),
    );
  }
}

// ── Action Column ────────────────────────────────────────────────────────────
class _ActionColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Play vs AI
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kPrimary, kPrimaryContainer],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.psychology, color: kOnPrimary, size: 36),
              const SizedBox(height: 16),
              Text('PLAY VS AI',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: kOnPrimary,
                      letterSpacing: -1)),
              const SizedBox(height: 6),
              Text('Grandmaster Difficulty • Stockfish v16',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kOnPrimary.withOpacity(0.8))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Multiplayer
        Container(
          decoration: BoxDecoration(
            color: kSurfaceContHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hub, color: kSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Multiplayer',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kOnSurface)),
                    Text('2,412 players online',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: kOnSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kOnSurfaceVariant),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tactical Feed ────────────────────────────────────────────────────────────
class _TacticalFeed extends StatelessWidget {
  final _items = const [
    _FeedItem(
      label: 'Resume Game',
      labelColor: kPrimary,
      title: 'Vs. Magnus_Bot',
      subtitle: 'Last move 2h ago',
      icon: Icons.play_arrow,
      iconBg: kSurfaceContHighest,
      iconColor: kOnSurfaceVariant,
    ),
    _FeedItem(
      label: 'Quick Start',
      labelColor: kOnSurfaceVariant,
      title: 'New Blitz Match',
      subtitle: '5 min + 2s inc',
      icon: Icons.add,
      iconBg: kSurfaceContHighest,
      iconColor: kOnSurfaceVariant,
    ),
    _FeedItem(
      label: 'Last Performance',
      labelColor: kSecondary,
      title: 'Victory vs Engine',
      subtitle: '+24 ELO Gained',
      icon: Icons.military_tech,
      iconBg: Color(0x1AA2E7FF),
      iconColor: kSecondary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _items
          .map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FeedCard(item: item),
              ))
          .toList(),
    );
  }
}

class _FeedCard extends StatelessWidget {
  final _FeedItem item;
  const _FeedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: item.labelColor,
                letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface)),
                  Text(item.subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: kOnSurfaceVariant)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedItem {
  final String label;
  final Color labelColor;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  const _FeedItem({
    required this.label,
    required this.labelColor,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });
}

// ── Pulsing Dot ──────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_anim.value),
          boxShadow: [
            BoxShadow(
                color: widget.color.withOpacity(_anim.value * 0.6),
                blurRadius: 6)
          ],
        ),
      ),
    );
  }
}
