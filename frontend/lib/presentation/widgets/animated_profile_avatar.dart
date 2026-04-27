import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ── Colour tokens ────────────────────────────────────────────────────────────
const _kSurfaceContHighest = Color(0xFF373431);
const _kPrimary = Color(0xFF8ADB52);
const _kPrimaryContainer = Color(0xFF68B631);
const _kSecondary = Color(0xFFA2E7FF);
const _kOutlineVariant = Color(0xFF414939);

/// An animated profile avatar with a rotating gradient border and glow pulse.
/// Tapping it navigates to the `/profile` route.
class AnimatedProfileAvatar extends StatefulWidget {
  /// Outer diameter of the entire widget (border + image).
  final double size;

  const AnimatedProfileAvatar({super.key, this.size = 36});

  @override
  State<AnimatedProfileAvatar> createState() => _AnimatedProfileAvatarState();
}

class _AnimatedProfileAvatarState extends State<AnimatedProfileAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _rotationCtrl;
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    // Slow-spinning gradient border
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Pulsing glow
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final borderWidth = size * 0.07; // ~2.5px at 36
    final innerSize = size - borderWidth * 2;

    return GestureDetector(
      onTap: () => context.push('/profile'),
      child: AnimatedBuilder(
        animation: Listenable.merge([_rotationCtrl, _glowAnim]),
        builder: (_, __) {
          final glowOpacity = 0.15 + _glowAnim.value * 0.35;

          return Container(
            margin: const EdgeInsets.only(right: 20, top: 8, bottom: 8),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(glowOpacity),
                  blurRadius: 12 + _glowAnim.value * 6,
                  spreadRadius: _glowAnim.value * 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Rotating gradient ring ──
                Transform.rotate(
                  angle: _rotationCtrl.value * 2 * math.pi,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const SweepGradient(
                        colors: [
                          _kPrimary,
                          _kSecondary,
                          _kPrimaryContainer,
                          _kPrimary,
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Inner image circle ──
                Container(
                  width: innerSize,
                  height: innerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kSurfaceContHighest,
                    border: Border.all(
                      color: _kOutlineVariant.withOpacity(0.2),
                      width: 0.5,
                    ),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/profile_avatar.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // ── Online indicator dot ──
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: size * 0.28,
                    height: size * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPrimary,
                      border: Border.all(
                        color: const Color(0xFF151311),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _kPrimary.withOpacity(0.6),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
