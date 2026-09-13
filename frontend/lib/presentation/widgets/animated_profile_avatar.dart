import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/user_provider.dart';
import '../theme/app_colors.dart';

/// A sleek, minimal name-based profile monogram avatar.
/// Derives initials from the user's display name.
/// Tapping it navigates to the `/profile` route.
class AnimatedProfileAvatar extends ConsumerWidget {
  /// Outer diameter of the entire widget.
  final double size;

  /// Optional override name. If null, reads from [userProfileProvider].
  final String? name;

  const AnimatedProfileAvatar({
    super.key,
    this.size = 36,
    this.name,
  });

  static String getInitials(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'P';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final displayName = name ?? profile?.displayName ?? 'Player';
    final initials = getInitials(displayName);

    return GestureDetector(
      onTap: () {
        final location = GoRouterState.of(context).uri.toString();
        if (!location.startsWith('/profile')) {
          context.push('/profile');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 16, top: 6, bottom: 6),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kPrimary,
          border: Border.all(
            color: kOutlineVariant.withValues(alpha: 0.6),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: Text(
                initials,
                style: GoogleFonts.outfit(
                  fontSize: size * 0.40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // Active status dot at bottom-right
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22C55E),
                  border: Border.all(
                    color: kBackground,
                    width: 1.5,
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

