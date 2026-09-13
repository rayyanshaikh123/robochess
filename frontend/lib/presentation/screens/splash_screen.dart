import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/session_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import 'onboarding_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  final Duration duration;

  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _navTimer;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn),
    );

    _animCtrl.forward();
    _startTimer();
  }

  void _startTimer() {
    _navTimer = Timer(widget.duration, _navigateNext);
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;

    try {
      final hasSeenOnboarding =
          await _storage.read(key: OnboardingScreen.storageKey);

      if (!mounted) return;

      if (hasSeenOnboarding != 'true') {
        // First-time users flow: Splash -> Onboarding -> Login
        context.go('/onboarding');
      } else {
        // Returning users flow: wait for secure-session restoration before routing.
        final sessionState = ref.read(sessionProvider);
        if (!sessionState.hasValue) {
          _navTimer = Timer(const Duration(milliseconds: 100), _navigateNext);
          return;
        }
        if (sessionState.valueOrNull != null) {
          context.go('/home');
        } else {
          context.go('/login');
        }
      }
    } catch (_) {
      if (mounted) {
        context.go('/onboarding');
      }
    }
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Tap anywhere to skip splash immediately
          _navTimer?.cancel();
          _navigateNext();
        },
        child: SafeArea(
          child: Stack(
            children: [
              // Center Branding
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Robochess App Logo
                        const AppLogo(
                          size: 130,
                          showBorder: false,
                          showShadow: false,
                        ),
                        const SizedBox(height: 28),

                        // Title in classical Cinzel
                        Text(
                          'ROBOCHESS',
                          style: GoogleFonts.cinzel(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: kOnSurface,
                            letterSpacing: 6,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Tagline in executive Outfit
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: kPrimary.withOpacity(0.2),
                            ),
                          ),
                          child: Text(
                            'AUTONOMOUS GRANDMASTER CRAFT',
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Status & Loading Indicator
              Positioned(
                left: 0,
                right: 0,
                bottom: 36,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 48,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const LinearProgressIndicator(
                            minHeight: 2.5,
                            backgroundColor: kSurfaceContHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'INITIALIZING TOURNAMENT SYSTEM',
                        style: GoogleFonts.outfit(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: kOnSurfaceVariant.withOpacity(0.8),
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
