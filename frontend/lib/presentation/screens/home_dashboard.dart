import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/game_state.dart';
import '../providers/game_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/chess_piece_widget.dart';
import '../widgets/animated_profile_avatar.dart';
import '../widgets/robo_app_bar.dart';

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

class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameControllerProvider).valueOrNull;
    final profileAsync = ref.watch(userProfileProvider);
    final statsAsync = ref.watch(userStatsProvider);

    final displayName = profileAsync.valueOrNull?.displayName ?? 'Player';
    final stats = statsAsync.valueOrNull;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: const RoboAppBar(
        sectionBadge: 'HOME',
        actions: [
          AnimatedProfileAvatar(size: 34),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GreetingCard(
                displayName: displayName, loading: profileAsync.isLoading),
            const SizedBox(height: 14),

            _StatsCard(
              loading: statsAsync.isLoading,
              gamesPlayed: stats?.gamesPlayed,
              wins: stats?.wins,
              losses: stats?.losses,
              draws: stats?.draws,
            ),
            const SizedBox(height: 20),

            _LiveBoardCard(game: game),
          ],
        ),
      ),
    );
  }
}

// ── Greeting ───────────────────────────────────────────
class _GreetingCard extends StatelessWidget {
  final String displayName;
  final bool loading;
  const _GreetingCard({required this.displayName, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: kSurfaceContLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOutlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: loading
          ? Container(
              width: 160,
              height: 14,
              decoration: BoxDecoration(
                color: kSurfaceContLow,
                borderRadius: BorderRadius.circular(99),
              ),
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kSurfaceContLow,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.waving_hand_rounded, color: kPrimary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: kOnSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface,
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

// ── Stats Row ───────────────────────────────────────────
class _StatsCard extends StatelessWidget {
  final bool loading;
  final int? gamesPlayed;
  final int? wins;
  final int? losses;
  final int? draws;
  const _StatsCard({
    required this.loading,
    this.gamesPlayed,
    this.wins,
    this.losses,
    this.draws,
  });

  @override
  Widget build(BuildContext context) {
    String text(int? value) => loading || value == null ? '—' : '$value';
    return Row(
      children: [
        Expanded(child: _stat('GAMES', text(gamesPlayed), kOnSurface)),
        const SizedBox(width: 6),
        Expanded(child: _stat('WINS', text(wins), kPrimary)),
        const SizedBox(width: 6),
        Expanded(child: _stat('LOSSES', text(losses), kError)),
        const SizedBox(width: 6),
        Expanded(child: _stat('DRAWS', text(draws), kSecondary)),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: kSurfaceContLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOutlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: kOnSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live Board Card ─────────────────────────────────────
class _LiveBoardCard extends StatelessWidget {
  final GameStateModel? game;
  const _LiveBoardCard({required this.game});

  List<List<String?>> _boardFromFen() {
    final fen = game?.currentFen;
    if (fen == null || fen.isEmpty) return _boardFromInitial();
    final parts = fen.split(' ');
    if (parts.isEmpty) return _boardFromInitial();

    final rows = parts[0].split('/');
    if (rows.length != 8) return _boardFromInitial();

    final board = <List<String?>>[];
    for (final r in rows) {
      final row = <String?>[];
      for (var i = 0; i < r.length; i++) {
        final c = r[i];
        final n = int.tryParse(c);
        if (n != null) {
          row.addAll(List.filled(n, null));
        } else {
          row.add(c);
        }
      }
      board.add(row);
    }
    return board.every((row) => row.length == 8) ? board : _boardFromInitial();
  }

  List<List<String?>> _boardFromInitial() =>
      _initialBoard.map((row) => row.map((piece) => piece).toList()).toList();

  @override
  Widget build(BuildContext context) {
    final board = _boardFromFen();
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kOutlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                game == null ? 'Tournament Board' : 'Live Game Position',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kOnSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  game == null ? 'READY' : 'ACTIVE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Inlaid Tournament Wooden Chessboard
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: kWoodFrame,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kWoodBrassAccent.withOpacity(0.4), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A2E1B).withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
                    final piece = board[row][col];

                    return Container(
                      color: isLight ? kWoodLightSquare : kWoodDarkSquare,
                      child: Center(
                        child: piece != null
                            ? Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: ChessPieceWidget(pieceSymbol: piece),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (game == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go('/play'),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  'START A GAME',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: kOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go('/play'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'RESUME GAME',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.go('/analysis'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: kOnPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'ANALYZE',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
