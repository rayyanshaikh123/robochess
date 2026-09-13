import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/puzzle_model.dart';
import '../providers/puzzle_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/chess_piece_widget.dart';

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
        backgroundColor: kBackground,
        appBar: AppBar(
          backgroundColor: kBackground,
          surfaceTintColor: Colors.transparent,
          title: Text('PUZZLE',
              style: GoogleFonts.cinzel(
                  fontWeight: FontWeight.w700, color: kPrimary, fontSize: 16)),
        ),
        body: Center(
          child: Text('Puzzle data not available.',
              style: GoogleFonts.inter(color: kOnSurfaceVariant)),
        ),
      );
    }

    final rating = puzzle.rating?.toString() ?? '—';
    final progress = puzzle.length == 0
        ? 'Move ${_moveIndex + 1}'
        : 'Move ${_moveIndex + 1} / ${puzzle.length}';

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Text('PUZZLE VAULT',
            style: GoogleFonts.cinzel(
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 2,
                fontSize: 16)),
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
          color: kWoodFrame,
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
              final piece = _game.get(squareName);

              final isSelected = squareName == _selectedSquare;
              final isLegalDest = _legalDestinations.contains(squareName);

              Color bgColor;
              if (isSelected) {
                bgColor = kPrimaryContainer.withOpacity(0.45);
              } else {
                bgColor = isLight ? kWoodLightSquare : kWoodDarkSquare;
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
                            border: Border.all(
                                color: kPrimary, width: 3),
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
                            '${8 - row}',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: isLight
                                  ? kWoodDarkSquare.withOpacity(0.85)
                                  : kWoodLightSquare.withOpacity(0.85),
                            ),
                          ),
                        ),
                      if (row == 7)
                        Positioned(
                          bottom: 2,
                          right: 3,
                          child: Text(
                            String.fromCharCode('a'.codeUnitAt(0) + col),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: isLight
                                  ? kWoodDarkSquare.withOpacity(0.85)
                                  : kWoodLightSquare.withOpacity(0.85),
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
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('RATING $rating',
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kSecondary,
                        letterSpacing: 1)),
              ),
              const Spacer(),
              Text(progress,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          completed ? kPrimary : kOnSurfaceVariant,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(completed ? 'Puzzle complete' : 'Tactical sequence',
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface)),
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

    Color color = kOnSurfaceVariant;
    if (submitting) {
      color = kSecondary;
    } else if (completed) {
      color = kPrimary;
    } else if (message != null && message!.startsWith('Incorrect')) {
      color = kError;
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
        color: kSurfaceContHighest,
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
              foregroundColor: kPrimary,
              side: BorderSide(color: kPrimary.withOpacity(0.6)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text('RESET PUZZLE',
                style: GoogleFonts.outfit(
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
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
      ),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: kOnSurfaceVariant,
              letterSpacing: 1)),
    );
  }
}
