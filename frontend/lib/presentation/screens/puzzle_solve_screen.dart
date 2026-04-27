import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/puzzle_model.dart';
import '../providers/puzzle_provider.dart';

const kPuzzleBackground = Color(0xFF151311);
const kPuzzleSurfaceLow = Color(0xFF1D1B19);
const kPuzzleSurfaceHigh = Color(0xFF2C2A27);
const kPuzzleSurfaceHighest = Color(0xFF373431);
const kPuzzlePrimary = Color(0xFF8ADB52);
const kPuzzleSecondary = Color(0xFFA2E7FF);
const kPuzzleOnPrimary = Color(0xFF173800);
const kPuzzleOnSurface = Color(0xFFE7E2DD);
const kPuzzleOnSurfaceVariant = Color(0xFFC0CAB4);
const kPuzzleOutlineVariant = Color(0xFF414939);
const kPuzzleError = Color(0xFFFFB4AB);

const _pieceSymbols = {
  'p': '♙',
  'n': '♘',
  'b': '♗',
  'r': '♖',
  'q': '♕',
  'k': '♔',
};

class PuzzleSolveScreen extends ConsumerStatefulWidget {
  final String puzzleId;
  final PuzzleModel? puzzle;

  const PuzzleSolveScreen({
    super.key,
    required this.puzzleId,
    required this.puzzle,
  });

  @override
  ConsumerState<PuzzleSolveScreen> createState() => _PuzzleSolveScreenState();
}

class _PuzzleSolveScreenState extends ConsumerState<PuzzleSolveScreen> {
  chess.Chess _game = chess.Chess();
  String? _selectedSquare;
  List<String> _legalDestinations = [];
  String? _feedback;
  bool _submitting = false;
  bool _completed = false;
  int _moveIndex = 0;
  String? _initialFen;

  @override
  void initState() {
    super.initState();
    final puzzle = widget.puzzle;
    if (puzzle != null && puzzle.fen.isNotEmpty) {
      _initialFen = puzzle.fen;
      _game = chess.Chess.fromFEN(puzzle.fen);
    }
  }

  String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = '${8 - row}';
    return '$file$rank';
  }

  void _onSquareTap(int row, int col) {
    if (_submitting || _completed || widget.puzzle == null) return;
    final square = _squareName(row, col);
    final piece = _game.get(square);

    if (_selectedSquare != null && _legalDestinations.contains(square)) {
      _attemptMove(_selectedSquare!, square);
      return;
    }

    if (piece != null && piece.color == _game.turn) {
      final moves = _game.generate_moves();
      final destinations = moves
          .where((m) => m.fromAlgebraic == square)
          .map((m) => m.toAlgebraic)
          .toList();
      setState(() {
        _selectedSquare = square;
        _legalDestinations = destinations;
      });
      return;
    }

    setState(() {
      _selectedSquare = null;
      _legalDestinations = [];
    });
  }

  String _buildUci(String from, String to) {
    final piece = _game.get(from);
    String? promotion;
    if (piece != null &&
        piece.type == chess.PieceType.PAWN &&
        (to[1] == '8' || to[1] == '1')) {
      promotion = 'q';
    }
    return '${from}${to}${promotion ?? ''}';
  }

  Future<void> _attemptMove(String from, String to) async {
    final puzzle = widget.puzzle;
    if (puzzle == null) return;
    final uci = _buildUci(from, to);

    setState(() {
      _submitting = true;
      _feedback = null;
      _selectedSquare = null;
      _legalDestinations = [];
    });

    try {
      final result = await ref.read(puzzleRepositoryProvider).attempt(
            puzzleId: puzzle.puzzleId,
            uci: uci,
            moveIndex: _moveIndex,
          );

      if (!mounted) return;

      if (result.correct) {
        final applied = _applyAttemptResult(
            result.nextFen, result.nextIndex, result.completed);
        setState(() {
          _feedback = applied
              ? (result.completed ? 'Puzzle solved.' : 'Correct move.')
              : 'Failed to load next position.';
        });
      } else {
        setState(() {
          _feedback = result.expectedUci == null
              ? 'Incorrect. Try again.'
              : 'Incorrect. Expected ${result.expectedUci}.';
        });
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _feedback = 'Attempt failed. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  bool _applyAttemptResult(String nextFen, int nextIndex, bool completed) {
    if (nextFen.isEmpty) {
      return true;
    }
    final loaded = _game.load(nextFen);
    if (!loaded) {
      return false;
    }
    _moveIndex = nextIndex;
    _completed = completed;
    _selectedSquare = null;
    _legalDestinations = [];
    return true;
  }

  void _resetPuzzle() {
    final fen = _initialFen;
    if (fen == null || fen.isEmpty) return;
    final loaded = _game.load(fen);
    if (!loaded) {
      setState(() => _feedback = 'Invalid puzzle position.');
      return;
    }
    setState(() {
      _moveIndex = 0;
      _completed = false;
      _feedback = null;
      _selectedSquare = null;
      _legalDestinations = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final puzzle = widget.puzzle;
    if (puzzle == null) {
      return Scaffold(
        backgroundColor: kPuzzleBackground,
        appBar: AppBar(
          backgroundColor: kPuzzleBackground,
          surfaceTintColor: Colors.transparent,
          title: Text('PUZZLE',
              style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700, color: kPuzzlePrimary)),
        ),
        body: Center(
          child: Text('Puzzle data not available.',
              style: GoogleFonts.inter(color: kPuzzleOnSurfaceVariant)),
        ),
      );
    }

    final rating = puzzle.rating?.toString() ?? '—';
    final progress = puzzle.length == 0
        ? 'Move ${_moveIndex + 1}'
        : 'Move ${_moveIndex + 1} / ${puzzle.length}';

    return Scaffold(
      backgroundColor: kPuzzleBackground,
      appBar: AppBar(
        backgroundColor: kPuzzleBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Text('PUZZLE VAULT',
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700,
                color: kPuzzlePrimary,
                letterSpacing: 2,
                fontSize: 14)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          children: [
            _PuzzleHeader(
              rating: rating,
              tags: puzzle.tags,
              progress: progress,
              completed: _completed,
            ),
            const SizedBox(height: 16),
            _buildChessBoard(),
            const SizedBox(height: 16),
            _PuzzleStatus(
              message: _feedback,
              submitting: _submitting,
              completed: _completed,
            ),
            const SizedBox(height: 12),
            _PuzzleActions(
              onReset: _resetPuzzle,
              disabled: _submitting,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChessBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: kPuzzleSurfaceHighest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: kPuzzlePrimary.withOpacity(0.05),
                blurRadius: 40,
                spreadRadius: 10)
          ],
        ),
        padding: const EdgeInsets.all(6),
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
            final piece = _game.get(squareName);

            final isSelected = squareName == _selectedSquare;
            final isLegalDest = _legalDestinations.contains(squareName);

            Color bgColor;
            if (isSelected) {
              bgColor = kPuzzlePrimary.withOpacity(0.35);
            } else {
              bgColor = isLight ? kPuzzleSurfaceHigh : kPuzzleSurfaceLow;
            }

            return GestureDetector(
              onTap: () => _onSquareTap(row, col),
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
                          color: kPuzzlePrimary.withOpacity(0.4),
                        ),
                      ),
                    if (isLegalDest && piece != null)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: kPuzzlePrimary.withOpacity(0.6), width: 3),
                        ),
                      ),
                    if (piece != null)
                      Text(
                        _pieceSymbols[piece.type.toString().toLowerCase()] ??
                            '',
                        style: TextStyle(
                          fontSize: 24,
                          color: piece.color == chess.Color.WHITE
                              ? kPuzzlePrimary
                              : kPuzzleSecondary,
                          shadows: [
                            Shadow(
                              color: (piece.color == chess.Color.WHITE
                                      ? kPuzzlePrimary
                                      : kPuzzleSecondary)
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
                        child: Text('${8 - row}',
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: isLight
                                    ? kPuzzleSurfaceLow
                                    : kPuzzleSurfaceHigh)),
                      ),
                    if (row == 7)
                      Positioned(
                        bottom: 1,
                        right: 2,
                        child: Text(
                            String.fromCharCode('a'.codeUnitAt(0) + col),
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: isLight
                                    ? kPuzzleSurfaceLow
                                    : kPuzzleSurfaceHigh)),
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

class _PuzzleHeader extends StatelessWidget {
  final String rating;
  final List<String> tags;
  final String progress;
  final bool completed;

  const _PuzzleHeader({
    required this.rating,
    required this.tags,
    required this.progress,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPuzzleSurfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPuzzleOutlineVariant.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kPuzzleSecondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('RATING $rating',
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kPuzzleSecondary,
                        letterSpacing: 1)),
              ),
              const Spacer(),
              Text(progress,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          completed ? kPuzzlePrimary : kPuzzleOnSurfaceVariant,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(completed ? 'Puzzle complete' : 'Tactical sequence',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kPuzzleOnSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.isEmpty
                ? const [_PuzzleTag(label: 'GENERAL')]
                : tags.take(4).map((tag) => _PuzzleTag(label: tag)).toList(),
          ),
        ],
      ),
    );
  }
}

class _PuzzleStatus extends StatelessWidget {
  final String? message;
  final bool submitting;
  final bool completed;

  const _PuzzleStatus({
    required this.message,
    required this.submitting,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    if (message == null && !submitting && !completed) {
      return const SizedBox.shrink();
    }

    Color color = kPuzzleOnSurfaceVariant;
    if (submitting) {
      color = kPuzzleSecondary;
    } else if (completed) {
      color = kPuzzlePrimary;
    } else if (message != null && message!.startsWith('Incorrect')) {
      color = kPuzzleError;
    }

    final text = submitting
        ? 'Checking move...'
        : completed
            ? 'Puzzle solved. Great work.'
            : message ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kPuzzleSurfaceHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _PuzzleActions extends StatelessWidget {
  final VoidCallback onReset;
  final bool disabled;

  const _PuzzleActions({
    required this.onReset,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: disabled ? null : onReset,
            style: OutlinedButton.styleFrom(
              foregroundColor: kPuzzlePrimary,
              side: BorderSide(color: kPuzzlePrimary.withOpacity(0.6)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text('RESET PUZZLE',
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

class _PuzzleTag extends StatelessWidget {
  final String label;
  const _PuzzleTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kPuzzleSurfaceLow,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: kPuzzleOutlineVariant.withOpacity(0.2)),
      ),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: kPuzzleOnSurfaceVariant,
              letterSpacing: 1)),
    );
  }
}
