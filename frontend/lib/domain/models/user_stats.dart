class UserStats {
  final int rating;
  final int globalRank;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;
  final double accuracy;
  final int puzzleAttempts;

  const UserStats({
    required this.rating,
    required this.globalRank,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
    required this.accuracy,
    required this.puzzleAttempts,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      rating: _toInt(json['rating']),
      globalRank: _toInt(json['global_rank']),
      gamesPlayed: _toInt(json['games_played']),
      wins: _toInt(json['wins']),
      losses: _toInt(json['losses']),
      draws: _toInt(json['draws']),
      winRate: _toDouble(json['win_rate']),
      accuracy: _toDouble(json['accuracy']),
      puzzleAttempts: _toInt(json['puzzle_attempts']),
    );
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
