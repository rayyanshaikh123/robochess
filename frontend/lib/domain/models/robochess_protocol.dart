import 'dart:convert';
import 'dart:math';

class ProtocolException implements Exception {
  final String message;
  ProtocolException(this.message);
  @override
  String toString() => 'ProtocolException: $message';
}

class RoboChessMessage {
  static const supportedVersion = 1;
  final int version;
  final String type;
  final int? seq;
  final String? id;
  final Map<String, dynamic> payload;

  const RoboChessMessage({
    required this.version,
    required this.type,
    this.seq,
    this.id,
    this.payload = const {},
  });

  factory RoboChessMessage.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final type = json['type'];
    if (version is! int || type is! String || type.isEmpty) {
      throw ProtocolException('Message requires integer version and type');
    }
    if (version != supportedVersion) {
      throw ProtocolException('Unsupported protocol version: $version');
    }
    final payload = Map<String, dynamic>.from(json);
    payload.removeWhere((key, _) => {'version', 'type', 'seq', 'id'}.contains(key));
    return RoboChessMessage(
      version: version,
      type: type,
      seq: json['seq'] is int ? json['seq'] as int : null,
      id: json['id']?.toString(),
      payload: payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'type': type,
        if (seq != null) 'seq': seq,
        if (id != null) 'id': id,
        ...payload,
      };

  String encode() => jsonEncode(toJson());
}

class ProtocolCommand {
  static final _random = Random();
  final String type;
  final int seq;
  final String id;
  final Map<String, dynamic> payload;

  ProtocolCommand(this.type, this.seq, this.payload)
      : id = '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}';

  RoboChessMessage toMessage() => RoboChessMessage(
        version: RoboChessMessage.supportedVersion,
        type: type,
        seq: seq,
        id: id,
        payload: payload,
      );
}

class PiState {
  final int version;
  final String state;
  final String? fen;
  final String? sessionId;
  final String? lastMove;
  final List<String> moveHistory;
  final String? engineState;
  final String? motionState;
  final String? recoveryReason;

  const PiState({
    required this.version,
    required this.state,
    this.fen,
    this.sessionId,
    this.lastMove,
    this.moveHistory = const [],
    this.engineState,
    this.motionState,
    this.recoveryReason,
  });

  factory PiState.fromMessage(RoboChessMessage message) {
    final p = message.payload;
    return PiState(
      version: (p['version_number'] as num?)?.toInt() ?? 0,
      state: p['state']?.toString() ?? message.type,
      fen: p['fen']?.toString(),
      sessionId: p['session_id']?.toString(),
      lastMove: p['last_move']?.toString(),
      moveHistory: (p['move_history'] as List? ?? const []).map((e) => '$e').toList(),
      engineState: p['engine_state']?.toString(),
      motionState: p['motion_state']?.toString(),
      recoveryReason: p['reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'state': state,
        if (fen != null) 'fen': fen,
        if (sessionId != null) 'session_id': sessionId,
        if (lastMove != null) 'last_move': lastMove,
        'move_history': moveHistory,
        if (engineState != null) 'engine_state': engineState,
        if (motionState != null) 'motion_state': motionState,
        if (recoveryReason != null) 'reason': recoveryReason,
      };
}
