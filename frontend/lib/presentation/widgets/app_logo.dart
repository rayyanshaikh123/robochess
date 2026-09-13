import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showBorder;
  final bool showShadow;
  final BorderRadius? borderRadius;

  const AppLogo({
    super.key,
    this.size = 56,
    this.showBorder = false,
    this.showShadow = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = Image.asset(
      'assets/images/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Icon(
            Icons.shield_rounded,
            size: size * 0.5,
            color: kPrimary,
          ),
        );
      },
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    if (!showBorder && !showShadow) {
      return SizedBox(
        width: size,
        height: size,
        child: imageWidget,
      );
    }

    final radius = borderRadius ?? BorderRadius.circular(size * 0.22);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: showBorder
            ? Border.all(
                color: kOutlineVariant.withValues(alpha: 0.5),
                width: 1.0,
              )
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: const Color(0x12000000),
                  blurRadius: size * 0.15,
                  offset: Offset(0, size * 0.04),
                ),
              ]
            : null,
      ),
      child: imageWidget,
    );
  }
}

