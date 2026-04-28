class GameStateModel {
  final String gameId;
  final String currentFen;
  final int gameVersion;
  final String? lastMove;

  GameStateModel({
    required this.gameId,
    required this.currentFen,
    required this.gameVersion,
    this.lastMove,
  });

  factory GameStateModel.fromJson(Map<String, dynamic> json) {
    return GameStateModel(
      gameId: json['game_id']?.toString() ?? '',
      currentFen:
          json['current_fen']?.toString() ?? json['fen']?.toString() ?? '',
      gameVersion: json['game_version'] is int
          ? json['game_version'] as int
          : int.tryParse(json['game_version']?.toString() ?? '0') ?? 0,
      lastMove: json['last_move']?.toString(),
    );
  }
}
