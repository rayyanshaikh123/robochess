import 'friend_model.dart';

/// A chat message inside a multiplayer game.
class GameChatMessage {
  final String messageId;
  final String userId;
  final String text;
  final DateTime? createdAt;

  const GameChatMessage({
    required this.messageId,
    required this.userId,
    required this.text,
    this.createdAt,
  });

  factory GameChatMessage.fromJson(Map<String, dynamic> json) {
    return GameChatMessage(
      messageId: json['message_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

/// A friend game as seen by one of its two players.
///
/// Every judgement (`yourTurn`, `yourResult`, colours) is computed by the
/// server; the client only renders it.
class MultiplayerGame {
  final String gameId;
  final String currentFen;
  final String status;
  final int gameVersion;
  final String? lastMove;
  final String? yourColor;
  final String? opponentColor;
  final String? turn;
  final bool yourTurn;
  final PublicUser opponent;
  final String? playMode;
  final String? yourSurface;
  final String? timeControlLabel;
  final int? yourRemainingMs;
  final int? opponentRemainingMs;
  final String? result;
  final String? yourResult;
  final String? winnerId;
  final String? endReason;
  final String? drawOfferBy;
  final DateTime? updatedAt;

  const MultiplayerGame({
    required this.gameId,
    required this.currentFen,
    required this.status,
    required this.gameVersion,
    required this.opponent,
    this.lastMove,
    this.yourColor,
    this.opponentColor,
    this.turn,
    this.yourTurn = false,
    this.playMode,
    this.yourSurface,
    this.timeControlLabel,
    this.yourRemainingMs,
    this.opponentRemainingMs,
    this.result,
    this.yourResult,
    this.winnerId,
    this.endReason,
    this.drawOfferBy,
    this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get playsOnBoard => yourSurface != null && yourSurface != 'app';
  bool get hasClock => yourRemainingMs != null;

  /// A draw this player must answer.
  bool get drawOfferedByOpponent =>
      drawOfferBy != null && drawOfferBy == opponent.userId;

  /// A draw this player offered and is waiting on.
  bool get drawOfferedByMe =>
      drawOfferBy != null && drawOfferBy != opponent.userId;

  MultiplayerGame copyWith({
    String? currentFen,
    String? status,
    int? gameVersion,
    String? lastMove,
    String? turn,
    bool? yourTurn,
    String? result,
    String? yourResult,
    String? winnerId,
    String? endReason,
    String? drawOfferBy,
    bool clearDrawOffer = false,
  }) {
    return MultiplayerGame(
      gameId: gameId,
      currentFen: currentFen ?? this.currentFen,
      status: status ?? this.status,
      gameVersion: gameVersion ?? this.gameVersion,
      lastMove: lastMove ?? this.lastMove,
      yourColor: yourColor,
      opponentColor: opponentColor,
      turn: turn ?? this.turn,
      yourTurn: yourTurn ?? this.yourTurn,
      opponent: opponent,
      playMode: playMode,
      yourSurface: yourSurface,
      timeControlLabel: timeControlLabel,
      yourRemainingMs: yourRemainingMs,
      opponentRemainingMs: opponentRemainingMs,
      result: result ?? this.result,
      yourResult: yourResult ?? this.yourResult,
      winnerId: winnerId ?? this.winnerId,
      endReason: endReason ?? this.endReason,
      drawOfferBy: clearDrawOffer ? null : (drawOfferBy ?? this.drawOfferBy),
      updatedAt: updatedAt,
    );
  }

  factory MultiplayerGame.fromJson(Map<String, dynamic> json) {
    final rawOpponent = json['opponent'];
    final opponent = PublicUser.fromJson(
      rawOpponent is Map ? Map<String, dynamic>.from(rawOpponent) : const {},
    );
    final rawTimeControl = json['time_control'];
    final rawClocks = json['clocks'];

    int? remainingFor(String? userId) {
      if (rawClocks is! Map || userId == null || userId.isEmpty) return null;
      final entry = rawClocks[userId];
      if (entry is! Map) return null;
      return _toIntOrNull(entry['remaining_ms']);
    }

    // The server keys clocks by user id; "yours" is whichever key is not the
    // opponent's.
    String? myKey;
    if (rawClocks is Map) {
      for (final key in rawClocks.keys) {
        if (key.toString() != opponent.userId) {
          myKey = key.toString();
          break;
        }
      }
    }

    return MultiplayerGame(
      gameId: json['game_id']?.toString() ?? '',
      currentFen: json['current_fen']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      gameVersion: _toIntOrNull(json['game_version']) ?? 0,
      lastMove: json['last_move']?.toString(),
      yourColor: json['your_color']?.toString(),
      opponentColor: json['opponent_color']?.toString(),
      turn: json['turn']?.toString(),
      yourTurn: json['your_turn'] == true,
      opponent: opponent,
      playMode: json['play_mode']?.toString(),
      yourSurface: json['your_surface']?.toString(),
      timeControlLabel:
          rawTimeControl is Map ? rawTimeControl['label']?.toString() : null,
      yourRemainingMs: remainingFor(myKey),
      opponentRemainingMs: remainingFor(opponent.userId),
      result: json['result']?.toString(),
      yourResult: json['your_result']?.toString(),
      winnerId: json['winner_id']?.toString(),
      endReason: json['end_reason']?.toString(),
      drawOfferBy: json['draw_offer_by']?.toString(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}
