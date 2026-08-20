import 'dart:convert';

class ProtocolException implements Exception {
  final String message;
  ProtocolException(this.message);
  @override
  String toString() => 'ProtocolException: $message';
}

/// Canonical wire envelope used by the Pi GATT server.
class RoboChessMessage {
  static const supportedVersion = '1';
  final String type;
  final String requestId;
  final String deviceId;
  final Map<String, dynamic> data;

  const RoboChessMessage({required this.type, required this.requestId, required this.deviceId, this.data = const {}});

  factory RoboChessMessage.fromJson(Map<String, dynamic> json) {
    if (json['version']?.toString() != supportedVersion || json['type'] is! String || json['data'] is! Map) {
      throw ProtocolException('Invalid RoboChess Pi envelope');
    }
    return RoboChessMessage(type: json['type'] as String, requestId: json['request_id']?.toString() ?? '', deviceId: json['device_id']?.toString() ?? '', data: Map<String, dynamic>.from(json['data'] as Map));
  }

  Map<String, dynamic> toJson() => {'version': supportedVersion, 'request_id': requestId, 'type': type, 'device_id': deviceId, 'data': data};
  String encode() => jsonEncode(toJson());
}

class PiState {
  final int version;
  final String state;
  final String? fen;
  final String? sessionId;
  final List<String> moveHistory;
  final String? recoveryReason;
  final bool gameOver;
  final String? result;

  const PiState({required this.version, required this.state, this.fen, this.sessionId, this.moveHistory = const [], this.recoveryReason, this.gameOver = false, this.result});

  String? get lastMove => moveHistory.isEmpty ? null : moveHistory.last;

  factory PiState.fromMessage(RoboChessMessage message) {
    final nested = message.data['engine_state'] ?? message.data['state'];
    final raw = nested is Map ? Map<String, dynamic>.from(nested) : message.data;
    return PiState(version: (raw['version'] as num?)?.toInt() ?? 0, state: raw['phase']?.toString() ?? message.data['status']?.toString() ?? message.type, fen: raw['fen']?.toString(), sessionId: raw['session_id']?.toString(), moveHistory: (raw['moves'] as List? ?? const []).map((item) => '$item').toList(), recoveryReason: raw['last_error']?.toString(), gameOver: raw['game_over'] == true, result: raw['result']?.toString());
  }

  Map<String, dynamic> toJson() => {'version': version, 'state': state, if (fen != null) 'fen': fen, if (sessionId != null) 'session_id': sessionId, 'moves': moveHistory, if (recoveryReason != null) 'last_error': recoveryReason, 'game_over': gameOver, if (result != null) 'result': result};
}
