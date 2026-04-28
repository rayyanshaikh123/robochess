import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:chess/chess.dart' as chess_lib;

import '../../domain/models/analysis_model.dart';

import '../providers/session_provider.dart';
import '../widgets/animated_profile_avatar.dart';

// ── Colour tokens ────────────────────────────────────────────────────────────
const _kBg = Color(0xFF151311);
const _kSurfLow = Color(0xFF1D1B19);
const _kSurfHigh = Color(0xFF2C2A27);
const _kSurfHighest = Color(0xFF373431);
const _kPrimary = Color(0xFF8ADB52);
const _kSecondary = Color(0xFFA2E7FF);
const _kOnSurf = Color(0xFFE7E2DD);
const _kOnSurfVar = Color(0xFFC0CAB4);
const _kOutline = Color(0xFF8A9480);
const _kOutlineVar = Color(0xFF414939);
const _kError = Color(0xFFFFB4AB);

// Unicode piece symbols
const _wp = {'K':'♔','Q':'♕','R':'♖','B':'♗','N':'♘','P':'♙'};

class AnalysisScreen extends ConsumerStatefulWidget {
  final String? gameId;
  const AnalysisScreen({super.key, this.gameId});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  AnalysisReport? _report;
  bool _loading = false;
  String? _error;
  int _currentMoveIdx = -1; // -1 = starting position
  String? _lastFetchedGameId; // tracks which game we last analyzed

  // Board state derived from the current move index
  chess_lib.Chess _board = chess_lib.Chess();

  @override
  void initState() {
    super.initState();
    if (widget.gameId != null) {
      _lastFetchedGameId = widget.gameId;
      _fetchAnalysis(widget.gameId!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pick up the game_id from the live route when navigating via go_router
    final routeGameId = GoRouterState.of(context).uri.queryParameters['game_id'];
    final effectiveId = routeGameId ?? widget.gameId;
    if (effectiveId != null && effectiveId != _lastFetchedGameId) {
      _lastFetchedGameId = effectiveId;
      _fetchAnalysis(effectiveId);
    }
  }

  Future<void> _fetchAnalysis(String gameId) async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = ref.read(gameRepositoryProvider);
      final report = await repo.fetchAnalysis(gameId);
      setState(() {
        _report = report;
        _loading = false;
        _currentMoveIdx = report.moves.length - 1;
        _rebuildBoard();
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _rebuildBoard() {
    _board = chess_lib.Chess();
    if (_report == null) return;
    for (int i = 0; i <= _currentMoveIdx && i < _report!.moves.length; i++) {
      _board.move({'from': _report!.moves[i].uci.substring(0, 2),
                   'to': _report!.moves[i].uci.substring(2, 4),
                   'promotion': _report!.moves[i].uci.length > 4
                       ? _report!.moves[i].uci[4] : null});
    }
  }

  void _goToMove(int idx) {
    if (_report == null) return;
    setState(() {
      _currentMoveIdx = idx.clamp(-1, _report!.moves.length - 1);
      _rebuildBoard();
    });
  }

  String _pieceAt(int row, int col) {
    final files = 'abcdefgh';
    final sq = '${files[col]}${8 - row}';
    final p = _board.get(sq);
    if (p == null) return '';
    final key = p.type.toUpperCase();
    final sym = _wp[key] ?? '';
    return sym;
  }

  Color _pieceColor(int row, int col) {
    final files = 'abcdefgh';
    final sq = '${files[col]}${8 - row}';
    final p = _board.get(sq);
    if (p == null) return Colors.transparent;
    return p.color == chess_lib.Color.WHITE ? _kPrimary : _kSecondary;
  }

  int get _currentEval {
    if (_report == null) return 0;
    final idx = _currentMoveIdx + 1; // evalScores[0] = before any move
    if (idx < 0 || idx >= _report!.evalScores.length) return 0;
    return _report!.evalScores[idx];
  }

  double get _evalBarFraction {
    // Map centipawns to 0.0 (black winning) – 1.0 (white winning)
    final cp = _currentEval.clamp(-1000, 1000);
    return (cp + 1000) / 2000.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('ROBOCHESS',
            style: GoogleFonts.spaceGrotesk(
                color: _kPrimary, fontWeight: FontWeight.w700,
                fontSize: 16, letterSpacing: 2)),
        centerTitle: true,
        actions: const [AnimatedProfileAvatar(size: 36), SizedBox(width: 16)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _buildError()
              : _report == null
                  ? _buildNoGame()
                  : _buildAnalysis(),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: _kError, size: 48),
      const SizedBox(height: 16),
      Text('Analysis Failed', style: GoogleFonts.spaceGrotesk(
          color: _kOnSurf, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_error!, textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: _kOnSurfVar, fontSize: 13))),
    ]),
  );

  Widget _buildNoGame() {
    final routeGameId = GoRouterState.of(context).uri.queryParameters['game_id'];
    final effectiveId = routeGameId ?? widget.gameId;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.analytics_outlined, color: _kOutline, size: 56),
        const SizedBox(height: 16),
        Text('No Game Selected', style: GoogleFonts.spaceGrotesk(
            color: _kOnSurf, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Play a game first, then tap Analyze.',
            style: GoogleFonts.inter(color: _kOnSurfVar, fontSize: 13)),
        if (effectiveId != null) ...[
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _fetchAnalysis(effectiveId),
            icon: const Icon(Icons.refresh),
            label: const Text('RETRY ANALYSIS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: const Color(0xFF173800),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildAnalysis() {
    final evalStr = (_currentEval >= 0 ? '+' : '') +
        (_currentEval.abs() >= 9999
            ? (_currentEval > 0 ? 'M' : '-M')
            : (_currentEval / 100).toStringAsFixed(1));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Column(children: [
        _buildBoardSection(evalStr),
        const SizedBox(height: 12),
        _buildNavControls(),
        const SizedBox(height: 16),
        _buildEvalGraph(),
        const SizedBox(height: 16),
        _buildMoveHistory(),
        const SizedBox(height: 16),
        if (_report!.aiInsight != null) _buildAiInsight(),
      ]),
    );
  }

  // ── Board ──────────────────────────────────────────────────────────────────
  Widget _buildBoardSection(String evalStr) {
    // Highlight squares of the current move
    String? fromSq, toSq;
    if (_currentMoveIdx >= 0 && _currentMoveIdx < _report!.moves.length) {
      final uci = _report!.moves[_currentMoveIdx].uci;
      fromSq = uci.substring(0, 2);
      toSq = uci.substring(2, 4);
    }

    return Container(
      decoration: BoxDecoration(color: _kSurfLow, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.analytics, color: _kPrimary, size: 20),
          const SizedBox(width: 8),
          Text(_currentMoveIdx < 0 ? 'STARTING POSITION' : 'MOVE ${_currentMoveIdx + 1}',
              style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: _kOnSurf)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _kSurfHighest, borderRadius: BorderRadius.circular(99)),
            child: Text('EVAL: $evalStr',
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _kOnSurfVar, letterSpacing: 1)),
          ),
        ]),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 1,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: _kSurfHighest),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
                itemCount: 64,
                itemBuilder: (context, index) {
                  final row = index ~/ 8, col = index % 8;
                  final isLight = (row + col) % 2 == 0;
                  final files = 'abcdefgh';
                  final sqName = '${files[col]}${8 - row}';
                  final isFrom = sqName == fromSq;
                  final isTo = sqName == toSq;
                  final highlighted = isFrom || isTo;

                  return Container(
                    decoration: BoxDecoration(
                      color: highlighted
                          ? _kPrimary.withValues(alpha: isTo ? 0.3 : 0.15)
                          : isLight ? _kSurfHigh : _kSurfLow,
                    ),
                    child: Stack(children: [
                      Center(child: Text(_pieceAt(row, col),
                          style: TextStyle(fontSize: 22, color: _pieceColor(row, col),
                              shadows: [Shadow(color: _pieceColor(row, col).withValues(alpha: 0.4), blurRadius: 6)]))),
                      if (col == 0) Positioned(top: 2, left: 3,
                          child: Text('${8 - row}', style: GoogleFonts.inter(fontSize: 7, fontWeight: FontWeight.w700,
                              color: isLight ? _kOnSurfVar : _kOutlineVar))),
                      if (row == 7) Positioned(bottom: 1, right: 3,
                          child: Text(files[col], style: GoogleFonts.inter(fontSize: 7, fontWeight: FontWeight.w700,
                              color: isLight ? _kOnSurfVar : _kOutlineVar))),
                    ]),
                  );
                },
              ),
            ),
            // Eval bar
            Positioned(left: 0, top: 0, bottom: 0, width: 8,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10)),
                child: Column(children: [
                  Expanded(flex: ((1 - _evalBarFraction) * 100).round().clamp(1, 99),
                      child: Container(color: _kBg)),
                  Expanded(flex: (_evalBarFraction * 100).round().clamp(1, 99),
                      child: Container(color: _kOnSurf)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Nav Controls ───────────────────────────────────────────────────────────
  Widget _buildNavControls() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _navBtn(Icons.skip_previous, () => _goToMove(-1)),
      const SizedBox(width: 8),
      _navBtn(Icons.chevron_left, () => _goToMove(_currentMoveIdx - 1)),
      const SizedBox(width: 8),
      // Move indicator
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: _kSurfLow, borderRadius: BorderRadius.circular(10)),
        child: Text(
          _currentMoveIdx < 0
              ? 'Start'
              : '${_currentMoveIdx + 1} / ${_report!.moves.length}',
          style: GoogleFonts.inter(color: _kOnSurf, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 8),
      _navBtn(Icons.chevron_right, () => _goToMove(_currentMoveIdx + 1)),
      const SizedBox(width: 8),
      _navBtn(Icons.skip_next, () => _goToMove(_report!.moves.length - 1)),
    ]);
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: _kSurfLow, borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10), onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10),
            child: Icon(icon, color: _kPrimary, size: 22)),
      ),
    );
  }

  // ── Eval Graph ─────────────────────────────────────────────────────────────
  Widget _buildEvalGraph() {
    final scores = _report!.evalScores;
    if (scores.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < scores.length; i++) {
      spots.add(FlSpot(i.toDouble(), (scores[i] / 100).clamp(-10, 10).toDouble()));
    }

    return Container(
      decoration: BoxDecoration(color: _kSurfLow, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EVALUATION GRAPH', style: GoogleFonts.spaceGrotesk(
            fontSize: 11, fontWeight: FontWeight.w600, color: _kOutline, letterSpacing: 2)),
        const SizedBox(height: 20),
        SizedBox(
          height: 160,
          child: LineChart(LineChartData(
            backgroundColor: Colors.transparent,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true, drawVerticalLine: false, horizontalInterval: 2,
              getDrawingHorizontalLine: (v) => FlLine(
                  color: v == 0 ? _kPrimary.withValues(alpha: 0.3) : _kOutlineVar.withValues(alpha: 0.15),
                  strokeWidth: v == 0 ? 1.5 : 0.5),
            ),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: LineTouchData(
              touchCallback: (event, response) {
                if (response?.lineBarSpots != null && response!.lineBarSpots!.isNotEmpty) {
                  final idx = response.lineBarSpots!.first.spotIndex;
                  _goToMove(idx - 1);
                }
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) =>
                    LineTooltipItem('${s.y >= 0 ? "+" : ""}${s.y.toStringAsFixed(1)}',
                        GoogleFonts.inter(color: _kPrimary, fontWeight: FontWeight.w700, fontSize: 11))
                ).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots, isCurved: true, curveSmoothness: 0.2,
                color: _kPrimary, barWidth: 2, isStrokeCapRound: true,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [_kPrimary.withValues(alpha: 0.15), Colors.transparent],
                  ),
                ),
              ),
            ],
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(y: 0, color: _kOutlineVar.withValues(alpha: 0.3), strokeWidth: 1),
            ]),
          )),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Move 1', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: _kOutline)),
          Text('Move ${_report!.moves.length}', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: _kOutline)),
        ]),
      ]),
    );
  }

  // ── Move History ───────────────────────────────────────────────────────────
  Widget _buildMoveHistory() {
    final moves = _report!.moves;
    // Group into pairs (white, black)
    final pairs = <List<AnalyzedMove>>[];
    for (int i = 0; i < moves.length; i += 2) {
      pairs.add([moves[i], if (i + 1 < moves.length) moves[i + 1]]);
    }

    return Container(
      decoration: BoxDecoration(color: _kSurfLow, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Move History', style: GoogleFonts.spaceGrotesk(
                fontSize: 17, fontWeight: FontWeight.w700, color: _kOnSurf)),
            Text('${moves.length} moves', style: GoogleFonts.inter(
                fontSize: 11, color: _kOutline)),
          ]),
        ),
        const Divider(color: _kOutlineVar, height: 1, thickness: 0.2),
        ...pairs.asMap().entries.map((entry) {
          final pairIdx = entry.key;
          final pair = entry.value;
          final moveNum = pairIdx + 1;
          return _buildMoveRow(moveNum, pair);
        }),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildMoveRow(int moveNum, List<AnalyzedMove> pair) {
    final white = pair[0];
    final black = pair.length > 1 ? pair[1] : null;
    final whiteIdx = (moveNum - 1) * 2;
    final blackIdx = whiteIdx + 1;
    final whiteSelected = _currentMoveIdx == whiteIdx;
    final blackSelected = black != null && _currentMoveIdx == blackIdx;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (whiteSelected || blackSelected) ? _kPrimary.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text('$moveNum.',
            style: GoogleFonts.inter(fontSize: 11, color: _kOutline,
                fontFeatures: [const FontFeature.tabularFigures()]))),
        Expanded(child: GestureDetector(
          onTap: () => _goToMove(whiteIdx),
          child: Row(children: [
            Text(white.san, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
                color: whiteSelected ? _kPrimary : _kOnSurf)),
            const SizedBox(width: 6),
            _tagChip(white.tag),
          ]),
        )),
        if (black != null)
          Expanded(child: GestureDetector(
            onTap: () => _goToMove(blackIdx),
            child: Row(children: [
              Text(black.san, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
                  color: blackSelected ? _kPrimary
                      : (black.tag == 'mistake' || black.tag == 'blunder') ? _kError : _kOnSurf)),
              const SizedBox(width: 6),
              _tagChip(black.tag),
            ]),
          ))
        else
          const Expanded(child: SizedBox.shrink()),
      ]),
    );
  }

  Widget _tagChip(String tag) {
    Color bg, fg;
    String label = tag;
    switch (tag) {
      case 'brilliant': bg = _kPrimary.withValues(alpha: 0.2); fg = _kPrimary; label = '!!'; break;
      case 'great': bg = _kPrimary.withValues(alpha: 0.15); fg = _kPrimary; label = '!'; break;
      case 'best': bg = _kSurfHighest; fg = _kOutline; break;
      case 'good': return const SizedBox.shrink();
      case 'inaccuracy': bg = const Color(0xFFFFC107).withValues(alpha: 0.2); fg = const Color(0xFFFFC107); label = '?!'; break;
      case 'mistake': bg = _kError.withValues(alpha: 0.2); fg = _kError; label = '?'; break;
      case 'blunder': bg = _kError.withValues(alpha: 0.3); fg = _kError; label = '??'; break;
      default: return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label.toUpperCase(), style: GoogleFonts.inter(
          fontSize: 9, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.5)),
    );
  }

  // ── AI Insight ─────────────────────────────────────────────────────────────
  Widget _buildAiInsight() {
    final insight = _report!.aiInsight!;
    return Container(
      decoration: BoxDecoration(
        color: _kSurfHighest, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.1)),
      ),
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0,
          child: Container(width: 4,
            decoration: const BoxDecoration(color: _kPrimary,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16), bottomLeft: Radius.circular(16))))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.psychology, color: _kPrimary, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ROBO-INSIGHT', style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, fontWeight: FontWeight.w700, color: _kPrimary, letterSpacing: 2)),
              const SizedBox(height: 8),
              RichText(text: TextSpan(
                style: GoogleFonts.inter(fontSize: 13, color: _kOnSurfVar, height: 1.6),
                children: [
                  const TextSpan(text: 'The engine suggests '),
                  TextSpan(text: insight.suggested,
                      style: GoogleFonts.inter(color: _kPrimary, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' instead of '),
                  TextSpan(text: insight.played,
                      style: GoogleFonts.inter(color: _kError, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' at move ${insight.moveNumber}. This cost approximately '),
                  TextSpan(text: '${(insight.cpSwing / 100).toStringAsFixed(1)} pawns',
                      style: GoogleFonts.inter(color: _kPrimary, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' of advantage.'),
                ],
              )),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  // Navigate to that move
                  final idx = _report!.moves.indexWhere((m) => m.moveNumber == insight.moveNumber);
                  if (idx >= 0) _goToMove(idx);
                },
                child: Row(children: [
                  Text('GO TO MOVE', style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w700, color: _kPrimary, letterSpacing: 2)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, color: _kPrimary, size: 14),
                ]),
              ),
            ])),
          ]),
        ),
      ]),
    );
  }
}
