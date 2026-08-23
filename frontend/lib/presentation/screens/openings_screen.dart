import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/animated_profile_avatar.dart';
import '../../domain/models/opening_context.dart';

// ── Colour tokens (matching the Learn Section palette) ───────────────────────
const _kBackground = Color(0xFF151311);
const _kSurfaceContLow = Color(0xFF1D1B19);
const _kSurfaceContHigh = Color(0xFF2C2A27);
const _kSurfaceContHighest = Color(0xFF373431);
const _kPrimary = Color(0xFF8ADB52);
const _kOnSurface = Color(0xFFE7E2DD);
const _kOnSurfaceVariant = Color(0xFFC0CAB4);
const _kOutlineVariant = Color(0xFF414939);
const _kOutline = Color(0xFF8A9480);

// ── Data model for an opening ────────────────────────────────────────────────
class _Opening {
  final String name;
  final String notation;
  final String style;
  final IconData styleIcon;
  final int difficultyDots; // out of 4

  const _Opening({
    required this.name,
    required this.notation,
    required this.style,
    required this.styleIcon,
    required this.difficultyDots,
  });
}

const _openings = [
  _Opening(
    name: 'Sicilian Defense',
    notation: '1. e4 c5',
    style: 'Aggressive',
    styleIcon: Icons.local_fire_department,
    difficultyDots: 3,
  ),
  _Opening(
    name: 'Ruy Lopez',
    notation: '1. e4 e5 2. Nf3 Nc6 3. Bb5',
    style: 'Solid',
    styleIcon: Icons.shield,
    difficultyDots: 2,
  ),
  _Opening(
    name: 'Caro-Kann',
    notation: '1. e4 c6',
    style: 'Solid',
    styleIcon: Icons.shield,
    difficultyDots: 4,
  ),
  _Opening(
    name: "King's Indian",
    notation: '1. d4 Nf6 2. c4 g6',
    style: 'Hypermodern',
    styleIcon: Icons.auto_awesome,
    difficultyDots: 3,
  ),
  _Opening(
    name: 'Queen\'s Gambit',
    notation: '1. d4 d5 2. c4',
    style: 'Gambits',
    styleIcon: Icons.whatshot,
    difficultyDots: 2,
  ),
  _Opening(
    name: 'French Defense',
    notation: '1. e4 e6',
    style: 'Solid',
    styleIcon: Icons.shield,
    difficultyDots: 3,
  ),
];

const _filterLabels = ['All Styles', 'Aggressive', 'Solid', 'Hypermodern', 'Gambits'];

class OpeningsScreen extends StatefulWidget {
  const OpeningsScreen({super.key});

  @override
  State<OpeningsScreen> createState() => _OpeningsScreenState();
}

class _OpeningsScreenState extends State<OpeningsScreen> {
  String _searchQuery = '';
  int _selectedFilter = 0;
  final _progressStorage = const FlutterSecureStorage();
  final Set<String> _startedOpenings = {};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final raw = await _progressStorage.read(key: 'started_openings');
    if (!mounted || raw == null || raw.isEmpty) return;
    setState(() => _startedOpenings.addAll(raw.split('\n')));
  }

  Future<void> _markStarted(String name) async {
    if (_startedOpenings.add(name)) {
      setState(() {});
      await _progressStorage.write(
        key: 'started_openings',
        value: _startedOpenings.join('\n'),
      );
    }
  }

  List<_Opening> get _filtered {
    var list = _openings.toList();
    // Apply style filter
    if (_selectedFilter > 0) {
      final style = _filterLabels[_selectedFilter];
      list = list.where((o) => o.style == style).toList();
    }
    // Apply search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) =>
          o.name.toLowerCase().contains(q) ||
          o.notation.toLowerCase().contains(q) ||
          o.style.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;

    return Scaffold(
      backgroundColor: _kBackground,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: _kBackground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: _kPrimary),
              onPressed: () => context.pop(),
            ),
            title: Text(
              'ROBOCHESS',
              style: GoogleFonts.spaceGrotesk(
                color: _kPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            centerTitle: true,
            actions: const [
              AnimatedProfileAvatar(size: 36),
              SizedBox(width: 16),
            ],
          ),

          // ── Header + Search + Filters ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'OPENINGS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: _kOnSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Master the first phase of the game. Access our curated library of classical and hypermodern setups.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: _kOnSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: _kSurfaceContHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.inter(
                        color: _kOnSurface,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search openings (e.g. Sicilian)',
                        hintStyle: GoogleFonts.inter(
                          color: _kOutline,
                          fontSize: 14,
                        ),
                        prefixIcon:
                            const Icon(Icons.search, color: _kOutlineVariant),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Filter chips
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filterLabels.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final selected = i == _selectedFilter;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedFilter = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _kPrimary.withOpacity(0.10)
                                  : _kSurfaceContLow,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: selected
                                    ? _kPrimary.withOpacity(0.25)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              _filterLabels[i],
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected ? _kPrimary : _kOnSurfaceVariant,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Openings Grid ────────────────────────────────────────────
          results.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 40),
                    child: Center(
                      child: Text(
                        'No openings match your search.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: _kOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                      child: _OpeningCard(
                        opening: results[index],
                        started: _startedOpenings.contains(results[index].name),
                        onPractice: _markStarted,
                      ),
                      ),
                      childCount: results.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Opening Card ─────────────────────────────────────────────────────────────
class _OpeningCard extends StatelessWidget {
  final _Opening opening;
  final bool started;
  final Future<void> Function(String name) onPractice;

  const _OpeningCard({
    required this.opening,
    required this.started,
    required this.onPractice,
  });

  void _openLesson(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSurfaceContLow,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(opening.name,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _kOnSurface)),
            const SizedBox(height: 6),
            Text('${opening.style} opening • ${opening.difficultyDots}/4 difficulty',
                style: GoogleFonts.inter(color: _kOnSurfaceVariant)),
            const SizedBox(height: 18),
            Text('Main line',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: _kPrimary)),
            const SizedBox(height: 6),
            Text(opening.notation,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, color: _kOnSurface)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onPractice(opening.name);
                  context.go(
                    '/play',
                    extra: OpeningContext(
                      name: opening.name,
                      pgn: opening.notation,
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('PRACTICE THIS OPENING'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openLesson(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
      decoration: BoxDecoration(
        color: _kSurfaceContLow,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative glow
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPrimary.withOpacity(0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row with style badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            opening.name,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _kOnSurface,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            opening.notation,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _kOnSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StyleBadge(
                      label: opening.style,
                      icon: opening.styleIcon,
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Bottom row: practice board + lesson metadata
                Row(
                  children: [
                    // Mini board visualizer
                    _MiniBoard(pgn: opening.notation),
                    const SizedBox(width: 16),

                    // Stats column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Difficulty dots
                          Row(
                            children: [
                              Icon(Icons.psychology,
                                  color: _kOutline, size: 16),
                              const SizedBox(width: 8),
                              ...List.generate(4, (i) {
                                final filled =
                                    i < opening.difficultyDots;
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(right: 4),
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: filled
                                          ? _kPrimary
                                          : _kSurfaceContHighest,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // The curriculum is static until lesson completion
                          // tracking is available from the backend.
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Practice line',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: _kOnSurfaceVariant,
                                ),
                              ),
                              Text(
                                started ? 'STARTED' : 'READY',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _kPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ── Style Badge ──────────────────────────────────────────────────────────────
class _StyleBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  const _StyleBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kSurfaceContHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kOnSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: _kOnSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini Board Visualizer ────────────────────────────────────────────────────
class _MiniBoard extends StatefulWidget {
  final String pgn;
  const _MiniBoard({required this.pgn});

  @override
  State<_MiniBoard> createState() => _MiniBoardState();
}

class _MiniBoardState extends State<_MiniBoard> {
  final chess_lib.Chess _board = chess_lib.Chess();
  
  @override
  void initState() {
    super.initState();
    _board.load_pgn(widget.pgn);
  }

  String _pieceAt(int row, int col) {
    final files = 'abcdefgh';
    final sq = '${files[col]}${8 - row}';
    final p = _board.get(sq);
    if (p == null) return '';
    const wp = {'K':'♔','Q':'♕','R':'♖','B':'♗','N':'♘','P':'♙'};
    return wp[p.type.toUpperCase()] ?? '';
  }

  Color _pieceColor(int row, int col) {
    final files = 'abcdefgh';
    final sq = '${files[col]}${8 - row}';
    final p = _board.get(sq);
    if (p == null) return Colors.transparent;
    return p.color == chess_lib.Color.WHITE ? _kPrimary : const Color(0xFFA2E7FF);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: _kSurfaceContHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kOutlineVariant.withOpacity(0.15)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
              itemCount: 64,
              itemBuilder: (context, index) {
                final row = index ~/ 8, col = index % 8;
                final isLight = (row + col) % 2 == 0;
                return Container(
                  color: isLight ? _kSurfaceContHigh : _kSurfaceContLow,
                  child: Center(
                    child: Text(
                      _pieceAt(row, col),
                      style: TextStyle(
                        fontSize: 10,
                        color: _pieceColor(row, col),
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: _pieceColor(row, col).withOpacity(0.4),
                            blurRadius: 2,
                          )
                        ]
                      ),
                    ),
                  ),
                );
              },
            ),
            // Gradient overlay for style
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      _kBackground.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
