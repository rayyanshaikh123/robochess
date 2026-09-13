import 'package:flutter/material.dart';

/// Renders a high-contrast tournament chess piece.
///
/// Supports either:
/// - [pieceSymbol]: e.g. 'P' (white pawn), 'p' (black pawn), 'wk' / 'bk', etc.
/// - or explicit [pieceType] ('k', 'q', 'r', 'b', 'n', 'p') and [isWhite].
class ChessPieceWidget extends StatelessWidget {
  final String? pieceSymbol;
  final String? pieceType;
  final bool? isWhite;
  final double? size;

  const ChessPieceWidget({
    super.key,
    this.pieceSymbol,
    this.pieceType,
    this.isWhite,
    this.size,
  });

  /// Factory constructor for `chess.Piece` or `chess_lib.Piece` duck typing.
  factory ChessPieceWidget.fromPiece({
    Key? key,
    required dynamic piece,
    double? size,
  }) {
    if (piece == null) {
      return ChessPieceWidget(key: key, pieceSymbol: null, size: size);
    }
    // Works with chess.Piece from package:chess
    final typeStr = piece.type?.toString().toLowerCase();
    final typeChar = typeStr != null && typeStr.isNotEmpty ? typeStr[typeStr.length - 1] : 'p';
    final colorStr = piece.color?.toString().toLowerCase() ?? '';
    final white = colorStr.contains('white') || piece.color == 0 || piece.color == true;

    return ChessPieceWidget(
      key: key,
      pieceType: typeChar,
      isWhite: white,
      size: size,
    );
  }

  static const _unicodeFallback = {
    'wk': '♔', 'wq': '♕', 'wr': '♖', 'wb': '♗', 'wn': '♘', 'wp': '♙',
    'bk': '♚', 'bq': '♛', 'br': '♜', 'bb': '♝', 'bn': '♞', 'bp': '♟',
  };

  @override
  Widget build(BuildContext context) {
    bool white = isWhite ?? true;
    String? type = pieceType?.toLowerCase();

    if (pieceSymbol != null && pieceSymbol!.isNotEmpty) {
      final sym = pieceSymbol!;
      if (sym.length == 2 && (sym.startsWith('w') || sym.startsWith('b'))) {
        white = sym.startsWith('w');
        type = sym[1].toLowerCase();
      } else if (sym.length == 1) {
        white = sym == sym.toUpperCase();
        type = sym.toLowerCase();
      }
    }

    if (type == null || type.isEmpty || !['k', 'q', 'r', 'b', 'n', 'p'].contains(type)) {
      return const SizedBox.shrink();
    }

    final key = '${white ? 'w' : 'b'}$type';
    final assetPath = 'assets/pieces/$key.png';

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Text(
        _unicodeFallback[key] ?? '',
        style: TextStyle(fontSize: (size ?? 24) * 0.8),
      ),
    );
  }
}
