import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum BoardThemeType {
  tournamentWood,
  tournamentGreen,
  birchTeak,
  modernSlate,
}

class BoardThemeConfig {
  final BoardThemeType type;
  final String id;
  final String name;
  final String description;
  final Color lightSquare;
  final Color darkSquare;
  final Color frameColor;
  final Color accentColor;

  const BoardThemeConfig({
    required this.type,
    required this.id,
    required this.name,
    required this.description,
    required this.lightSquare,
    required this.darkSquare,
    required this.frameColor,
    required this.accentColor,
  });
}

const kBoardThemes = [
  BoardThemeConfig(
    type: BoardThemeType.tournamentWood,
    id: 'tournament_wood',
    name: 'Tournament Wood',
    description: 'Handcrafted Boxwood & Walnut with Teak frame',
    lightSquare: Color(0xFFF0D9B5),
    darkSquare: Color(0xFFB58863),
    frameColor: Color(0xFF3D2415),
    accentColor: Color(0xFFC88A22),
  ),
  BoardThemeConfig(
    type: BoardThemeType.tournamentGreen,
    id: 'tournament_green',
    name: 'Tournament Green',
    description: 'Championship Buff White & Pine Green combo',
    lightSquare: Color(0xFFEEEED2),
    darkSquare: Color(0xFF224D33),
    frameColor: Color(0xFF1B2B20),
    accentColor: Color(0xFF1B4332),
  ),
  BoardThemeConfig(
    type: BoardThemeType.birchTeak,
    id: 'birch_teak',
    name: 'Birch & Teak',
    description: 'Scandinavian Light Birch & Deep Teak',
    lightSquare: Color(0xFFE8D5B7),
    darkSquare: Color(0xFF8C532B),
    frameColor: Color(0xFF2E170A),
    accentColor: Color(0xFFC88A22),
  ),
  BoardThemeConfig(
    type: BoardThemeType.modernSlate,
    id: 'modern_slate',
    name: 'Modern Slate',
    description: 'Minimal Ice & Cool Slate contrast',
    lightSquare: Color(0xFFF1F5F9),
    darkSquare: Color(0xFF475569),
    frameColor: Color(0xFF0F172A),
    accentColor: Color(0xFF1B4332),
  ),
];

class BoardThemeNotifier extends StateNotifier<BoardThemeConfig> {
  static const _storageKey = 'selected_chessboard_theme';
  final FlutterSecureStorage _storage;

  BoardThemeNotifier(this._storage) : super(kBoardThemes[0]) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final savedId = await _storage.read(key: _storageKey);
      if (savedId != null) {
        final match = kBoardThemes.firstWhere(
          (t) => t.id == savedId,
          orElse: () => kBoardThemes[0],
        );
        state = match;
      }
    } catch (_) {}
  }

  Future<void> setTheme(BoardThemeConfig theme) async {
    state = theme;
    try {
      await _storage.write(key: _storageKey, value: theme.id);
    } catch (_) {}
  }
}

final boardThemeProvider =
    StateNotifierProvider<BoardThemeNotifier, BoardThemeConfig>((ref) {
  return BoardThemeNotifier(const FlutterSecureStorage());
});
