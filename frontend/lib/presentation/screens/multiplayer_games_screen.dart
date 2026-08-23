import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/multiplayer_game_model.dart';
import '../providers/multiplayer_game_provider.dart';

// ── Colour tokens ──────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);
const kError = Color(0xFFFFB4AB);

class MultiplayerGamesScreen extends ConsumerStatefulWidget {
  const MultiplayerGamesScreen({super.key});

  @override
  ConsumerState<MultiplayerGamesScreen> createState() =>
      _MultiplayerGamesScreenState();
}

class _MultiplayerGamesScreenState
    extends ConsumerState<MultiplayerGamesScreen> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final games = _showHistory
        ? ref.watch(gameHistoryProvider)
        : ref.watch(activeGamesProvider);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: kOnSurfaceVariant),
          onPressed: () => context.go('/friends'),
        ),
        title: Text('YOUR GAMES',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 2)),
        actions: [
          IconButton(
            tooltip: 'Friends',
            onPressed: () => context.go('/friends'),
            icon: const Icon(Icons.group, color: kOnSurfaceVariant),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kPrimary,
        backgroundColor: kSurfaceContLow,
        onRefresh: () async {
          await ref
              .read(_showHistory
                  ? gameHistoryProvider.notifier
                  : activeGamesProvider.notifier)
              .load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            Row(
              children: [
                Expanded(
                  child: _toggle('ACTIVE', !_showHistory,
                      () => setState(() => _showHistory = false)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _toggle('HISTORY', _showHistory,
                      () => setState(() => _showHistory = true)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            games.when(
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _showHistory
                          ? 'No finished games yet.'
                          : 'No games in progress. Challenge a friend to start one.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: kOnSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: items
                      .map((game) => _GameCard(
                            game: game,
                            onOpen: () =>
                                context.go('/friends/game/${game.gameId}'),
                          ))
                      .toList(),
                );
              },
              loading: () => const LinearProgressIndicator(
                backgroundColor: kSurfaceContHighest,
                valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
                minHeight: 6,
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Could not load your games. Pull to retry.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: kOnSurfaceVariant)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? kPrimary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? kPrimary : kOutlineVariant.withOpacity(0.2)),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: selected ? kPrimary : kOnSurfaceVariant)),
        ),
      );
}

class _GameCard extends StatelessWidget {
  final MultiplayerGame game;
  final VoidCallback onOpen;

  const _GameCard({required this.game, required this.onOpen});

  String get _statusLine {
    if (game.isCompleted) {
      final reason = switch (game.endReason) {
        'checkmate' => 'checkmate',
        'resignation' => 'resignation',
        'timeout' => 'time',
        'draw_agreed' => 'agreement',
        'stalemate' => 'stalemate',
        _ => game.endReason ?? 'end',
      };
      final outcome = switch (game.yourResult) {
        'won' => 'You won',
        'lost' => 'You lost',
        'draw' => 'Draw',
        _ => 'Finished',
      };
      return '$outcome by $reason';
    }
    return game.yourTurn ? 'Your move' : 'Waiting for opponent';
  }

  Color get _statusColor {
    if (!game.isCompleted) return game.yourTurn ? kPrimary : kOnSurfaceVariant;
    return switch (game.yourResult) {
      'won' => kPrimary,
      'lost' => kError,
      _ => kSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: kSurfaceContHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person, color: kOnSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.opponent.displayName,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kOnSurface)),
                const SizedBox(height: 2),
                Text(_statusLine,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _statusColor)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (game.yourColor != null) 'You: ${game.yourColor}',
                    if (game.timeControlLabel != null) game.timeControlLabel!,
                    if (game.lastMove != null) 'Last: ${game.lastMove}',
                  ].join('  ·  '),
                  style: GoogleFonts.inter(
                      fontSize: 10, color: kOnSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onOpen,
            child: Text(game.isCompleted ? 'REVIEW' : 'CONTINUE',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: kPrimary)),
          ),
        ],
      ),
    );
  }
}
