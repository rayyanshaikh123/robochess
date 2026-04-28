/// Data models for the game analysis report returned by
/// `GET /game/{game_id}/analysis`.

class AnalysisReport {
  final String gameId;
  final int totalMoves;
  final List<AnalyzedMove> moves;
  final List<int> evalScores;
  final AiInsight? aiInsight;

  const AnalysisReport({
    required this.gameId,
    required this.totalMoves,
    required this.moves,
    required this.evalScores,
    this.aiInsight,
  });

  factory AnalysisReport.fromJson(Map<String, dynamic> json) {
    return AnalysisReport(
      gameId: json['game_id']?.toString() ?? '',
      totalMoves: (json['total_moves'] as int?) ?? 0,
      moves: (json['moves'] as List<dynamic>? ?? [])
          .map((m) => AnalyzedMove.fromJson(m as Map<String, dynamic>))
          .toList(),
      evalScores: (json['eval_scores'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      aiInsight: json['ai_insight'] != null
          ? AiInsight.fromJson(json['ai_insight'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AnalyzedMove {
  final int moveNumber;
  final String uci;
  final String san;
  final bool isWhite;
  final int scoreBefore;
  final int scoreAfter;
  final int cpLoss;
  final String tag;
  final String? bestMoveUci;
  final String? bestMoveSan;
  final String fenAfter;

  const AnalyzedMove({
    required this.moveNumber,
    required this.uci,
    required this.san,
    required this.isWhite,
    required this.scoreBefore,
    required this.scoreAfter,
    required this.cpLoss,
    required this.tag,
    this.bestMoveUci,
    this.bestMoveSan,
    required this.fenAfter,
  });

  factory AnalyzedMove.fromJson(Map<String, dynamic> json) {
    return AnalyzedMove(
      moveNumber: (json['move_number'] as num?)?.toInt() ?? 0,
      uci: json['uci']?.toString() ?? '',
      san: json['san']?.toString() ?? '',
      isWhite: json['is_white'] as bool? ?? true,
      scoreBefore: (json['score_before'] as num?)?.toInt() ?? 0,
      scoreAfter: (json['score_after'] as num?)?.toInt() ?? 0,
      cpLoss: (json['cp_loss'] as num?)?.toInt() ?? 0,
      tag: json['tag']?.toString() ?? 'good',
      bestMoveUci: json['best_move_uci']?.toString(),
      bestMoveSan: json['best_move_san']?.toString(),
      fenAfter: json['fen_after']?.toString() ?? '',
    );
  }
}

class AiInsight {
  final int moveNumber;
  final String played;
  final String suggested;
  final int cpSwing;
  final String summary;

  const AiInsight({
    required this.moveNumber,
    required this.played,
    required this.suggested,
    required this.cpSwing,
    required this.summary,
  });

  factory AiInsight.fromJson(Map<String, dynamic> json) {
    return AiInsight(
      moveNumber: (json['move_number'] as num?)?.toInt() ?? 0,
      played: json['played']?.toString() ?? '',
      suggested: json['suggested']?.toString() ?? '',
      cpSwing: (json['cp_swing'] as num?)?.toInt() ?? 0,
      summary: json['summary']?.toString() ?? '',
    );
  }
}
