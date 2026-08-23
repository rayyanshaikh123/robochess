import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/game_state.dart';
import '../providers/game_provider.dart';
import '../providers/user_provider.dart';

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
const kError = Color(0xFFFFB4AB);

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
      body: SafeArea(
        child: SingleChildScrollView(
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
              const SizedBox(height: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: kPrimary, width: 4)),
      ),
      child: loading
          ? Container(
              width: 160,
              height: 14,
              decoration: BoxDecoration(
                color: kSurfaceContHighest,
                borderRadius: BorderRadius.circular(99),
              ),
            )
          : Row(
              children: [
                const Icon(Icons.waving_hand, color: kPrimary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Welcome back, $displayName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface,
                    ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('GAMES', text(gamesPlayed), kOnSurface),
          _stat('WINS', text(wins), kPrimary),
          _stat('LOSSES', text(losses), kError),
          _stat('DRAWS', text(draws), kSecondary),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: kOnSurfaceVariant,
                letterSpacing: 1)),
      ],
    );
  }
}

// ── Live Board ──────────────────────────────────────────
class _LiveBoardCard extends StatelessWidget {
  final GameStateModel? game;

  const _LiveBoardCard({this.game});

  List<List<String?>> _boardFromFen() {
    if (game == null || game!.currentFen.isEmpty) {
      return _boardFromInitial();
    }
    final placement = game!.currentFen.split(' ').first;
    final rows = placement.split('/');
    if (rows.length != 8) return _boardFromInitial();
    final board = rows.map((row) {
      final cells = <String?>[];
      for (final char in row.split('')) {
        final empty = int.tryParse(char);
        if (empty != null) {
          cells.addAll(List<String?>.filled(empty, null));
        } else {
          cells.add(char);
        }
      }
      return cells.length == 8 ? cells : <String?>[];
    }).toList();
    return board.every((row) => row.length == 8) ? board : _boardFromInitial();
  }

  List<List<String?>> _boardFromInitial() =>
      _initialBoard.map((row) => row.map((piece) => piece).toList()).toList();

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
    final board = _boardFromFen();
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            game == null ? 'Ready for a Game' : 'Live Game Position',
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
                  final piece = board[row][col];

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
          const SizedBox(height: 16),
          if (game == null)
            FilledButton.icon(
              onPressed: () => context.go('/play'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('START A GAME'),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/play'),
                  icon: const Icon(Icons.play_circle),
                  label: const Text('RESUME GAME'),
                ),
                const SizedBox(width: 10),
                Text(
                  'Move ${game!.gameVersion}${game!.lastMove == null ? '' : ' • ${game!.lastMove}'}',
                  style:
                      GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
