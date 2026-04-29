import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../widgets/animated_profile_avatar.dart';
import '../providers/puzzle_provider.dart';
import '../../domain/models/puzzle_model.dart';
import 'dart:math' as math;

// ── Colour tokens ────────────────────────────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHigh = Color(0xFF2C2A27);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kPrimaryContainer = Color(0xFF68B631);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kTertiary = Color(0xFF97D77E);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);
const kError = Color(0xFFFFB4AB);

class LearnSection extends ConsumerWidget {
  const LearnSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          const AnimatedProfileAvatar(size: 36),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero Section ────────────────────────────────────────
                _HeroSection(),
                const SizedBox(height: 32),

                // ── Category Cards Grid ──────────────────────────────────
                _CategoryGrid(),
                const SizedBox(height: 24),

                // ── Puzzle Vault ──────────────────────────────────────────
                _PuzzleVault(),
                const SizedBox(height: 24),

                // ── Secondary Bento Row ──────────────────────────────────
                _BentoRow(),
              ],
            ),
          ),

          // ── Continue Lesson FAB ──────────────────────────────────────
          Positioned(
            bottom: 100,
            right: 20,
            child: _ContinueFAB(),
          ),
        ],
      ),
    );
  }
}

// ── Hero Section ─────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title block
        Text('NEURAL TRAINING MODULE',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 2)),
        const SizedBox(height: 10),
        Text('GRANDMASTER',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: kOnSurface,
                letterSpacing: -1,
                height: 1)),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [kPrimary, kSecondary],
          ).createShader(bounds),
          child: Text('ACADEMY',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1,
                  height: 1.1)),
        ),
        const SizedBox(height: 14),
        Text(
          'Refine your algorithmic intuition. Our neural processing units have analyzed 400 million grandmaster games to prepare your next evolution.',
          style: GoogleFonts.inter(
              fontSize: 13, color: kOnSurfaceVariant, height: 1.6),
        ),
        const SizedBox(height: 24),
        // Level tracker circle
        _LevelTracker(),
      ],
    );
  }
}

// ── Level Tracker ─────────────────────────────────────────────────────────────
class _LevelTracker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: CustomPaint(
              painter: _CircleProgressPainter(progress: 0.75),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('RANK',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 2)),
                    Text('12',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: kOnSurface)),
                    Text('75% SYNC',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: kSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: kSecondary.withOpacity(0.2)),
            ),
            child: Text('ADVANCED ENGINE',
                style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: kSecondary,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  const _CircleProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final strokeWidth = 7.0;

    // Background circle
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = kSurfaceContHighest
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth);

    // Progress arc
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = kPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_CircleProgressPainter old) => old.progress != progress;
}

// ── Category Grid ─────────────────────────────────────────────────────────────
class _CategoryGrid extends StatelessWidget {
  final _categories = const [
    _Category(
      title: 'Mastering Openings',
      description:
          'Systematically secure center control with robotic precision and deep theory.',
      badge: '6 Lessons',
      badgeColor: kPrimary,
      iconData: Icons.memory,
      iconBg: Color(0x208ADB52),
      route: '/learn/openings',
    ),
    _Category(
      title: 'Endgame Strategy',
      description:
          'Master the attrition phase. Turn minimal advantages into forced mechanical victories.',
      badge: '12 Lessons',
      badgeColor: kSecondary,
      iconData: Icons.precision_manufacturing,
      iconBg: Color(0x20A2E7FF),
    ),
    _Category(
      title: 'Tactical Drills',
      description:
          'High-frequency pattern recognition modules to sharpen your real-time response.',
      badge: 'Daily Drills',
      badgeColor: kTertiary,
      iconData: Icons.bolt,
      iconBg: Color(0x2097D77E),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _categories
          .map((cat) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CategoryCard(category: cat),
              ))
          .toList(),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _Category category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: category.route != null
          ? () => context.push(category.route!)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: kSurfaceContLow,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder with badge
            Stack(
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  color: kSurfaceContHighest,
                  child: Center(
                    child: Icon(category.iconData,
                        color: category.badgeColor.withOpacity(0.3), size: 56),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kSurfaceContHighest.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: category.badgeColor.withOpacity(0.2)),
                    ),
                    child: Text(category.badge.toUpperCase(),
                        style: GoogleFonts.inter(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: category.badgeColor,
                            letterSpacing: 1)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.title,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface)),
                  const SizedBox(height: 6),
                  Text(category.description,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: kOnSurfaceVariant, height: 1.5)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: category.iconBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(category.iconData,
                            color: category.badgeColor, size: 14),
                      ),
                      Row(
                        children: [
                          Text('INITIALIZE',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kPrimary,
                                  letterSpacing: 2)),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward,
                              color: kPrimary, size: 16),
                        ],
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

class _Category {
  final String title, description, badge;
  final Color badgeColor, iconBg;
  final IconData iconData;
  final String? route;
  const _Category({
    required this.title,
    required this.description,
    required this.badge,
    required this.badgeColor,
    required this.iconBg,
    required this.iconData,
    this.route,
  });
}

// ── Bento Row ─────────────────────────────────────────────────────────────────
class _BentoRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Neural Analysis
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: kSurfaceContLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Neural Analysis',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface)),
                  const Icon(Icons.psychology, color: kPrimary, size: 28),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Upload your physical games for AI deep-learning analysis and error detection.',
                style: GoogleFonts.inter(
                    fontSize: 13, color: kOnSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: 0.33,
                  backgroundColor: kSurfaceContHighest,
                  valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text('3 GAMES ANALYZED THIS WEEK',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      letterSpacing: 2)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // IoT Board Sync
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kSurfaceContLow, kSurfaceContHighest],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kOutlineVariant.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IoT Board Sync',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const SizedBox(height: 8),
              Text(
                'Connect your physical RoboChess unit to stream real-time tutorials directly to the board.',
                style: GoogleFonts.inter(
                    fontSize: 13, color: kOnSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kBackground,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: kSecondary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulsingDot(color: kSecondary),
                    const SizedBox(width: 8),
                    Text('READY TO SYNC',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kSecondary,
                            letterSpacing: 2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Continue Lesson FAB ───────────────────────────────────────────────────────
class _ContinueFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimary, kPrimaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: kPrimary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow, color: kOnPrimary, size: 20),
                const SizedBox(width: 8),
                Text('CONTINUE LESSON',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kOnPrimary,
                        letterSpacing: 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Puzzle Vault ───────────────────────────────────────────────────────────
class _PuzzleVault extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzles = ref.watch(puzzleControllerProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOutlineVariant.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.extension, color: kSecondary, size: 20),
              const SizedBox(width: 8),
              Text('PUZZLE VAULT',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface,
                      letterSpacing: 1)),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    ref.read(puzzleControllerProvider.notifier).load(limit: 20),
                icon: const Icon(Icons.refresh, color: kOnSurfaceVariant),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Solve curated positions synced from the backend. Your progress fuels the training matrix.',
            style: GoogleFonts.inter(
                fontSize: 12, color: kOnSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 16),
          puzzles.when(
            data: (items) {
              if (items.isEmpty) {
                return Text('No puzzles available yet.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: kOnSurfaceVariant));
              }
              final count = items.length > 5 ? 5 : items.length;
              return ListView.separated(
                itemCount: count,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final puzzle = items[index];
                  return _PuzzleCard(puzzle: puzzle);
                },
              );
            },
            loading: () => const LinearProgressIndicator(
              backgroundColor: kSurfaceContHighest,
              valueColor: AlwaysStoppedAnimation<Color>(kSecondary),
              minHeight: 6,
            ),
            error: (err, _) => Text('Failed to load puzzles.',
                style: GoogleFonts.inter(fontSize: 12, color: kError)),
          ),
        ],
      ),
    );
  }
}

class _PuzzleCard extends StatelessWidget {
  final PuzzleModel puzzle;

  const _PuzzleCard({required this.puzzle});

  @override
  Widget build(BuildContext context) {
    final rating = puzzle.rating?.toString() ?? '—';
    final tags = puzzle.tags;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
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
              Text('${puzzle.length} MOVES',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kOnSurfaceVariant,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Tactical sequence ready',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.isEmpty
                ? [const _PuzzleTag(label: 'GENERAL')]
                : tags.take(3).map((tag) => _PuzzleTag(label: tag)).toList(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: kPrimary,
              ),
              onPressed: () {
                context.push('/learn/puzzle/${puzzle.puzzleId}', extra: puzzle);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SOLVE',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
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

// ── Pulsing Dot ───────────────────────────────────────────────────────────────
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
