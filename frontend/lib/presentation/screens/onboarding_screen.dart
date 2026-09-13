import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/chess_piece_widget.dart';
import '../widgets/app_logo.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String storageKey = 'has_seen_onboarding_v1';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  int _currentPage = 0;

  final List<_OnboardingItem> _slides = const [
    _OnboardingItem(
      title: "Autonomous Robotic Chess",
      subtitle: "Where Classical Craftsmanship Meets Advanced Robotics",
      description:
          "Experience chess on a physical tournament wooden board driven by precision gantry stepper motors and magnetic piece actuation.",
      icon: Icons.precision_manufacturing_rounded,
      highlightPiece: 'wk',
      badgeText: "PHYSICAL ROBOTICS",
    ),
    _OnboardingItem(
      title: "Dual Link & Telemetry",
      subtitle: "Effortless Bluetooth & Wi-Fi Synchronization",
      description:
          "Link your RoboChess board in seconds. Send moves via mobile tap, voice command, or watch the robotic arm play autonomous grandmaster moves.",
      icon: Icons.bluetooth_connected_rounded,
      highlightPiece: 'wn',
      badgeText: "SMART CONNECT",
    ),
    _OnboardingItem(
      title: "Tactics, Openings & AI",
      subtitle: "Powered by Grandmaster Stockfish Engine",
      description:
          "Deep post-game blunder analysis, curated master opening repertoires, and tactical puzzle training tailored to your rating.",
      icon: Icons.psychology_rounded,
      highlightPiece: 'wq',
      badgeText: "AI INTELLIGENCE",
    ),
  ];

  Future<void> _completeOnboarding() async {
    await _storage.write(key: OnboardingScreen.storageKey, value: 'true');
    if (mounted) {
      context.go('/login');
    }
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Navigation Bar ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const AppLogo(size: 30, showBorder: false, showShadow: false),
                      const SizedBox(width: 9),
                      Text(
                        "ROBOCHESS",
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kOnSurface,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _completeOnboarding,
                    style: TextButton.styleFrom(
                      foregroundColor: kOnSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: Text(
                      "Skip",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Main Page Slider ────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Decorative Card with Wooden Bevel & Piece
                        Container(
                          width: double.infinity,
                          height: 230,
                          decoration: BoxDecoration(
                            color: kSurfaceContLow,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: kOutlineVariant, width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Subtle Wooden Inlay Grid Pattern
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: Opacity(
                                    opacity: 0.25,
                                    child: GridView.builder(
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6),
                                      itemCount: 24,
                                      itemBuilder: (_, i) => Container(
                                        color: (i ~/ 6 + i % 6) % 2 == 0 ? kWoodLightSquare : kWoodDarkSquare,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Hero Piece Card
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  color: kSurfaceContLowest,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kWoodBrassAccent.withValues(alpha: 0.6), width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimary.withValues(alpha: 0.18),
                                      blurRadius: 18,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                                padding: const EdgeInsets.all(14),
                                child: ChessPieceWidget(
                                  pieceSymbol: slide.highlightPiece,
                                  size: 85,
                                ),
                              ),
                              // Top-Right Feature Badge
                              Positioned(
                                top: 16,
                                right: 16,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: kPrimary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    slide.badgeText,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: kOnPrimary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Title & Subtitle
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cinzel(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: kOnSurface,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          slide.subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: kOnSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Bottom Action Bar & Page Indicators ──────────────
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators
                  Row(
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i ? kPrimary : kOutlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // Next / Get Started Button
                  FilledButton(
                    onPressed: _nextPage,
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: kOnPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == _slides.length - 1 ? "GET STARTED" : "CONTINUE",
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
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

class _OnboardingItem {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final String highlightPiece;
  final String badgeText;

  const _OnboardingItem({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.highlightPiece,
    required this.badgeText,
  });
}
