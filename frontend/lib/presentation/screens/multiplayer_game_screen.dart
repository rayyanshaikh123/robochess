import 'dart:async';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/errors/api_exception.dart';
import '../../domain/models/multiplayer_game_model.dart';
import '../providers/multiplayer_game_provider.dart';
import '../providers/social_provider.dart';
import '../widgets/chess_board_view.dart';

// ── Colour tokens ──────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLowest = Color(0xFF0F0E0C);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHigh = Color(0xFF2C2A27);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);
const kError = Color(0xFFFFB4AB);

class MultiplayerGameScreen extends ConsumerStatefulWidget {
  final String gameId;
  const MultiplayerGameScreen({super.key, required this.gameId});

  @override
  ConsumerState<MultiplayerGameScreen> createState() =>
      _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState
    extends ConsumerState<MultiplayerGameScreen> {
  final chess.Chess _board = chess.Chess();
  final _chatController = TextEditingController();

  String? _selectedSquare;
  Set<String> _legalDestinations = {};
  String? _renderedFen;
  bool _busy = false;
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = ref
        .read(multiplayerGameProvider(widget.gameId).notifier)
        .notices
        .listen(_toast);
  }

  @override
  void dispose() {
    _notices?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Keep the local board in step with the server's FEN.
  void _syncBoard(MultiplayerGame game) {
    if (_renderedFen == game.currentFen) return;
    if (game.currentFen.isEmpty) return;
    if (_board.load(game.currentFen)) {
      _renderedFen = game.currentFen;
      _selectedSquare = null;
      _legalDestinations = {};
    }
  }

  void _onSquareTap(String square, MultiplayerGame game) {
    if (!game.isActive || !game.yourTurn || _busy) return;
    // A board-backed player moves the physical pieces instead.
    if (game.playsOnBoard) return;

    if (_selectedSquare != null && _legalDestinations.contains(square)) {
      _submit(_selectedSquare!, square, game);
      return;
    }

    final piece = _board.get(square);
    final myColor =
        game.yourColor == 'white' ? chess.Color.WHITE : chess.Color.BLACK;
    if (piece == null || piece.color != myColor) {
      setState(() {
        _selectedSquare = null;
        _legalDestinations = {};
      });
      return;
    }

    setState(() {
      _selectedSquare = square;
      _legalDestinations = _legalMovesFrom(square);
    });
  }

  Set<String> _legalMovesFrom(String square) {
    final destinations = <String>{};
    for (final move in _board.generate_moves()) {
      if (move.fromAlgebraic == square) destinations.add(move.toAlgebraic);
    }
    return destinations;
  }

  Future<void> _submit(String from, String to, MultiplayerGame game) async {
    // Promotion is always to a queen, matching the single-player screen.
    final piece = _board.get(from);
    final isPromotion = piece != null &&
        piece.type == chess.PieceType.PAWN &&
        (to.endsWith('8') || to.endsWith('1'));
    final uci = '$from$to${isPromotion ? 'q' : ''}';

    setState(() {
      _busy = true;
      _selectedSquare = null;
      _legalDestinations = {};
    });
    try {
      await ref
          .read(multiplayerGameProvider(widget.gameId).notifier)
          .submitMove(uci);
    } on ApiException catch (err) {
      // The server rejected it; its FEN is the truth, so resync.
      _toast(err.details?['detail']?.toString() ?? err.message);
      await ref.read(multiplayerGameProvider(widget.gameId).notifier).refresh();
    } catch (_) {
      _toast('Could not send your move.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (err) {
      _toast(err.message);
    } catch (_) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmResign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurfaceContLow,
        title: const Text('Resign?'),
        content: const Text('Are you sure you want to resign this game?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guard(
        () => ref.read(multiplayerGameProvider(widget.gameId).notifier).resign());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiplayerGameProvider(widget.gameId));
    final controller =
        ref.read(multiplayerGameProvider(widget.gameId).notifier);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: kOnSurfaceVariant),
          onPressed: () => context.go('/friends/games'),
        ),
        title: Text('FRIEND GAME',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 2)),
      ),
      body: state.when(
        data: (game) {
          _syncBoard(game);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (!controller.socketConnected)
                const _Banner(
                    text: 'Reconnecting...', color: kSecondary),
              _PlayerBar(
                name: game.opponent.displayName,
                colorLabel: game.opponentColor ?? '',
                remainingMs: game.opponentRemainingMs,
                active: game.isActive && !game.yourTurn,
                online: controller.opponentOnline,
              ),
              const SizedBox(height: 10),
              ChessBoardView(
                game: _board,
                interactive:
                    game.isActive && game.yourTurn && !game.playsOnBoard,
                flipped: game.yourColor == 'black',
                selectedSquare: _selectedSquare,
                legalDestinations: _legalDestinations,
                onSquareTap: (square) => _onSquareTap(square, game),
              ),
              const SizedBox(height: 10),
              _PlayerBar(
                name: 'You',
                colorLabel: game.yourColor ?? '',
                remainingMs: game.yourRemainingMs,
                active: game.isActive && game.yourTurn,
                online: true,
              ),
              const SizedBox(height: 16),
              _StatusPanel(game: game),
              const SizedBox(height: 16),
              if (game.isActive) _buildControls(game, controller),
              if (game.isCompleted) _buildFinished(game),
              const SizedBox(height: 20),
              _ChatPanel(
                messages: controller.chat,
                controller: _chatController,
                onSend: (text) => _guard(() => controller.sendChat(text)),
              ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              err is ApiException ? err.message : 'Could not load this game.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
      MultiplayerGame game, MultiplayerGameController controller) {
    if (game.drawOfferedByOpponent) {
      return Row(
        children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kPrimary, foregroundColor: kOnPrimary),
              onPressed: _busy
                  ? null
                  : () => _guard(() => controller.respondToDraw(true)),
              child: const Text('ACCEPT DRAW'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _guard(() => controller.respondToDraw(false)),
              child: const Text('DECLINE'),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy || game.drawOfferedByMe
                ? null
                : () => _guard(() => controller.offerDraw()),
            icon: const Icon(Icons.handshake_outlined, size: 16),
            label: Text(
                game.drawOfferedByMe ? 'DRAW OFFERED' : 'OFFER DRAW',
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kError),
            onPressed: _busy ? null : _confirmResign,
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: Text('RESIGN',
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildFinished(MultiplayerGame game) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: kPrimary, foregroundColor: kOnPrimary),
        onPressed: _busy
            ? null
            : () => _guard(() async {
                  await ref
                      .read(challengesProvider.notifier)
                      .rematch(widget.gameId);
                  _toast('Rematch offered to ${game.opponent.displayName}');
                }),
        icon: const Icon(Icons.refresh, size: 18),
        label: Text('OFFER REMATCH',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2)),
      ),
    );
  }

}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  const _Banner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

class _PlayerBar extends StatelessWidget {
  final String name;
  final String colorLabel;
  final int? remainingMs;
  final bool active;
  final bool online;

  const _PlayerBar({
    required this.name,
    required this.colorLabel,
    required this.remainingMs,
    required this.active,
    required this.online,
  });

  String get _clock {
    final ms = remainingMs;
    if (ms == null) return '';
    final total = (ms / 1000).floor();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? kPrimary : kOutlineVariant.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? kPrimary : kOnSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kOnSurface)),
          ),
          if (colorLabel.isNotEmpty)
            Text(colorLabel.toUpperCase(),
                style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: kOnSurfaceVariant)),
          if (_clock.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? kPrimary.withOpacity(0.15) : kSurfaceContHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_clock,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: active ? kPrimary : kOnSurfaceVariant)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final MultiplayerGame game;
  const _StatusPanel({required this.game});

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;

    if (game.isCompleted) {
      final reason = switch (game.endReason) {
        'checkmate' => 'by checkmate',
        'resignation' => 'by resignation',
        'timeout' => 'on time',
        'draw_agreed' => 'by agreement',
        'stalemate' => 'by stalemate',
        _ => '',
      };
      text = switch (game.yourResult) {
        'won' => 'You won $reason',
        'lost' => 'You lost $reason',
        'draw' => 'Draw $reason',
        _ => 'Game finished',
      };
      color = switch (game.yourResult) {
        'won' => kPrimary,
        'lost' => kError,
        _ => kSecondary,
      };
    } else if (game.playsOnBoard) {
      text = 'Play your move on the physical board.';
      color = kSecondary;
    } else if (game.yourTurn) {
      text = 'Your move.';
      color = kPrimary;
    } else {
      text = 'Waiting for ${game.opponent.displayName}...';
      color = kOnSurfaceVariant;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceContLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          if (game.lastMove != null) ...[
            const SizedBox(height: 4),
            Text('Last move: ${game.lastMove}',
                style: GoogleFonts.inter(
                    fontSize: 11, color: kOnSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  final List<GameChatMessage> messages;
  final TextEditingController controller;
  final void Function(String) onSend;

  const _ChatPanel({
    required this.messages,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHAT',
              style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: kOnSurfaceVariant)),
          const SizedBox(height: 10),
          if (messages.isEmpty)
            Text('No messages yet.',
                style:
                    GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                children: messages
                    .map((message) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(message.text,
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: kOnSurface)),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: GoogleFonts.inter(fontSize: 13, color: kOnSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Say something',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 12, color: kOnSurfaceVariant),
                    filled: true,
                    fillColor: kSurfaceContLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isEmpty) return;
                    onSend(value.trim());
                    controller.clear();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 18, color: kPrimary),
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  onSend(text);
                  controller.clear();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
