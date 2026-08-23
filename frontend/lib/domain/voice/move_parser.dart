import 'package:chess/chess.dart' as chess;
import 'move_parse_result.dart';

/// Port of VoiceModule/move_parser.py
///
/// Converts spoken or typed text into UCI move strings.
/// Validates moves against the current board position when provided.

// ── Vocabulary maps ──────────────────────────────────────────────────────────

const _fileMap = {
  'a': 'a', 'alpha': 'a',
  'b': 'b', 'bravo': 'b', 'bee': 'b', 'be': 'b',
  'c': 'c', 'charlie': 'c', 'see': 'c', 'sea': 'c',
  'd': 'd', 'delta': 'd', 'dee': 'd',
  'e': 'e', 'echo': 'e',
  'f': 'f', 'foxtrot': 'f', 'eff': 'f',
  'g': 'g', 'golf': 'g', 'gee': 'g', 'ji': 'g', 'jee': 'g',
  'h': 'h', 'hotel': 'h', 'aitch': 'h', 'ach': 'h',
};

const _rankMap = {
  '1': '1', 'one': '1',
  '2': '2', 'two': '2', 'to': '2', 'too': '2',
  '3': '3', 'three': '3',
  '4': '4', 'four': '4', 'for': '4',
  '5': '5', 'five': '5',
  '6': '6', 'six': '6',
  '7': '7', 'seven': '7',
  '8': '8', 'eight': '8', 'ate': '8',
};

const _promotionMap = {
  'queen': 'q', 'q': 'q',
  'rook': 'r', 'r': 'r',
  'bishop': 'b', 'b': 'b',
  'knight': 'n', 'n': 'n',
  'king': 'q', // fallback mispronunciation → queen
};

const _skipWords = {'to', 'takes', 'captures', 'x', 'goes', 'moves', 'at', 'on'};

/// Words that double as both connectors and rank digits ('to' → '2',
/// 'for' → '4'). Inside [_parseSquare] they must never be consumed as a
/// rank — the skip loop handles them as connectors instead.
const _connectorWords = {'to', 'too', 'for'};

// ── Normalisation ────────────────────────────────────────────────────────────

String _normalize(String text) {
  text = text.toLowerCase().trim();
  text = text.replaceAll(RegExp(r'[^\w\s]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

// ── Square parser ────────────────────────────────────────────────────────────

/// Try to read a chess square starting at tokens[idx].
/// Returns (squareStr, nextIdx) or (null, idx).
(String?, int) _parseSquare(List<String> tokens, int idx) {
  if (idx >= tokens.length) return (null, idx);

  final tok = tokens[idx];

  // Single token already looks like a square: "d4", "e2"
  if (tok.length == 2 &&
      'abcdefgh'.contains(tok[0]) &&
      '12345678'.contains(tok[1])) {
    return (tok, idx + 1);
  }

  // File word
  if (_fileMap.containsKey(tok)) {
    final fileChar = _fileMap[tok]!;
    if (idx + 1 < tokens.length &&
        _rankMap.containsKey(tokens[idx + 1]) &&
        !_connectorWords.contains(tokens[idx + 1])) {
      // Make sure the next token isn't a "skip word" being used as a rank
      // "to" and "for" could be connectors, but they're also in _rankMap
      // Only treat as rank if the previous token is a file
      final rankChar = _rankMap[tokens[idx + 1]]!;
      return ('$fileChar$rankChar', idx + 2);
    }
  }

  return (null, idx);
}

// ── Public API ───────────────────────────────────────────────────────────────

/// Parse spoken or typed text into a chess move.
///
/// If [board] is provided, validates the move against legal moves.
/// Returns a [MoveParseResult] with either a UCI string or error.
MoveParseResult parseMove(String text, [chess.Chess? board]) {
  text = _normalize(text);
  final tokens = text.split(' ');

  if (tokens.isEmpty || (tokens.length == 1 && tokens[0].isEmpty)) {
    return const MoveParseResult.failure('Nothing entered');
  }

  final first = tokens[0];

  // ── Special commands ──────────────────────────────────────────────────
  if (['quit', 'exit', 'resign'].contains(first)) {
    return const MoveParseResult.command('QUIT');
  }
  if (first == 'undo') {
    return const MoveParseResult.command('UNDO');
  }
  if (first == 'help') {
    return const MoveParseResult.command('HELP');
  }

  // ── Castling ──────────────────────────────────────────────────────────
  const castleWords = {'castle', 'castles', 'castling', '0-0', 'o-o'};
  if (castleWords.contains(first) || tokens.any((w) => castleWords.contains(w))) {
    final kingside = tokens.any((w) => ['king', 'kingside', 'short'].contains(w));
    final queenside = tokens.any((w) => ['queen', 'queenside', 'long'].contains(w));

    if (board != null) {
      // Generate legal castling moves
      final moves = board.generate_moves();
      for (final move in moves) {
        final moveStr = move.toAlgebraic;
        final isKingsideCastle = moveStr == 'O-O';
        final isQueensideCastle = moveStr == 'O-O-O';

        if (isKingsideCastle || isQueensideCastle) {
          if (kingside && isKingsideCastle) {
            return MoveParseResult.success(move.fromAlgebraic + move.toAlgebraic);
          }
          if (queenside && isQueensideCastle) {
            return MoveParseResult.success(move.fromAlgebraic + move.toAlgebraic);
          }
          if (!kingside && !queenside) {
            return MoveParseResult.success(move.fromAlgebraic + move.toAlgebraic);
          }
        }
      }
      return const MoveParseResult.failure('Castling is not available right now');
    }

    // No board — return a best-guess castling move
    if (queenside) {
      return const MoveParseResult.success('e1c1'); // white queenside
    }
    return const MoveParseResult.success('e1g1'); // white kingside default
  }

  // ── Standard move: SRC [skip] DEST [promotion] ────────────────────────
  final (src, srcIdx) = _parseSquare(tokens, 0);
  if (src == null) {
    return const MoveParseResult.failure(
      "Couldn't read a source square — say e.g. D2 TO D4",
    );
  }

  // Skip connector words
  var idx = srcIdx;
  while (idx < tokens.length && _skipWords.contains(tokens[idx])) {
    idx++;
  }

  final (dest, destIdx) = _parseSquare(tokens, idx);
  if (dest == null) {
    return const MoveParseResult.failure(
      "Couldn't read a destination square — say e.g. D2 TO D4",
    );
  }

  // ── Optional promotion piece ──────────────────────────────────────────
  String? promotion;
  idx = destIdx;
  if (idx < tokens.length) {
    final word = tokens[idx];
    if (word == 'promote') {
      idx++;
      if (idx < tokens.length && tokens[idx] == 'to') idx++;
      if (idx < tokens.length && _promotionMap.containsKey(tokens[idx])) {
        promotion = _promotionMap[tokens[idx]];
      }
    } else if (_promotionMap.containsKey(word)) {
      promotion = _promotionMap[word];
    }
  }

  // ── Build UCI string ──────────────────────────────────────────────────
  var uci = '$src$dest';
  if (promotion != null) uci += promotion;

  // ── Validate against legal moves (if board provided) ──────────────────
  if (board != null) {
    if (board.move({'from': src, 'to': dest, 'promotion': promotion ?? 'q'})) {
      board.undo(); // We just tested legality, undo the move
      return MoveParseResult.success(uci);
    }

    // Maybe it's a pawn needing promotion but none was specified
    if (promotion == null) {
      for (final piece in ['q', 'r', 'b', 'n']) {
        if (board.move({'from': src, 'to': dest, 'promotion': piece})) {
          board.undo();
          return MoveParseResult.failure(
            'Promotion needed — say ${src.toUpperCase()} TO '
            '${dest.toUpperCase()} QUEEN (or ROOK / BISHOP / KNIGHT)',
          );
        }
      }
    }

    return MoveParseResult.failure('$uci is not a legal move in this position');
  }

  return MoveParseResult.success(uci);
}
