import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'app_logo.dart';

/// Standard, unified top bar template used across all primary RoboChess screens.
/// Guarantees consistent brand presentation, logo display, typography, and safe navigation.
class RoboAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? sectionBadge;
  final bool showLogo;
  final bool showBackButton;
  final String? fallbackRoute;
  final List<Widget>? actions;
  final Widget? leading;

  const RoboAppBar({
    super.key,
    this.title = 'ROBOCHESS',
    this.sectionBadge,
    this.showLogo = true,
    this.showBackButton = false,
    this.fallbackRoute,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    Widget? leadingWidget = leading;

    if (leadingWidget == null && showBackButton) {
      leadingWidget = IconButton(
        icon: const Icon(Icons.arrow_back, color: kOnSurface),
        tooltip: 'Back',
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else if (fallbackRoute != null) {
            context.go(fallbackRoute!);
          }
        },
      );
    }

    return AppBar(
      backgroundColor: kBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      leading: leadingWidget,
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLogo) ...[
              const AppLogo(size: 30, showBorder: false, showShadow: false),
              const SizedBox(width: 9),
            ],
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kOnSurface,
                letterSpacing: 2,
              ),
            ),
            if (sectionBadge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kPrimary.withOpacity(0.2)),
                ),
                child: Text(
                  sectionBadge!,
                  style: GoogleFonts.outfit(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: kOutlineVariant.withOpacity(0.5),
          height: 0.8,
        ),
      ),
    );
  }
}
