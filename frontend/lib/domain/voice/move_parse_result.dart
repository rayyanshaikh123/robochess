/// Result of parsing spoken or typed text into a chess move.
class MoveParseResult {
  /// UCI move string (e.g. "e2e4") or special command: QUIT, UNDO, HELP.
  final String? uci;

  /// Human-readable error message if parsing failed.
  final String? error;

  /// Whether this result represents a special command rather than a move.
  bool get isCommand =>
      uci != null && (uci == 'QUIT' || uci == 'UNDO' || uci == 'HELP');

  /// Whether parsing succeeded (has a UCI string and no error).
  bool get isSuccess => uci != null && error == null;

  const MoveParseResult({this.uci, this.error});

  const MoveParseResult.success(String this.uci) : error = null;
  const MoveParseResult.failure(String this.error) : uci = null;
  const MoveParseResult.command(String this.uci) : error = null;

  @override
  String toString() => isSuccess ? 'Move($uci)' : 'Error($error)';
}
