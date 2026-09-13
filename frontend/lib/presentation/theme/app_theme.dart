import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: kBackground,
      primaryColor: kPrimary,
      colorScheme: const ColorScheme.light(
        primary: kPrimary,
        surface: kSurfaceContLowest,
        onPrimary: kOnPrimary,
        onSurface: kOnSurface,
        secondary: kSecondary,
        error: kError,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.light().textTheme.copyWith(
              displayLarge: const TextStyle(color: kOnSurface, fontWeight: FontWeight.bold),
              bodyLarge: const TextStyle(color: kOnSurface),
              bodyMedium: const TextStyle(color: kOnSurfaceVariant),
            ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: kBackground,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: kPrimary),
        titleTextStyle: TextStyle(
          color: kOnSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: kSurfaceContLowest,
        selectedItemColor: kPrimary,
        unselectedItemColor: kOnSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 6,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: kOnPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: kOnPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      cardTheme: CardThemeData(
        color: kSurfaceContLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kOutlineVariant.withOpacity(0.5)),
        ),
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;
}
