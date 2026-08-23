import 'friend_model.dart';

/// A selectable time control, as offered by `/challenges/time-controls`.
class TimeControlOption {
  final String key;
  final String label;
  final int? initialSeconds;
  final int? incrementSeconds;

  const TimeControlOption({
    required this.key,
    required this.label,
    this.initialSeconds,
    this.incrementSeconds,
  });

  bool get isUnlimited => initialSeconds == null;

  factory TimeControlOption.fromJson(Map<String, dynamic> json) {
    return TimeControlOption(
      key: json['key']?.toString() ?? 'unlimited',
      label: json['label']?.toString() ?? 'Unlimited',
      initialSeconds: _toIntOrNull(json['initial_seconds']),
      incrementSeconds: _toIntOrNull(json['increment_seconds']),
    );
  }
}

/// A game challenge, incoming or outgoing.
class ChallengeModel {
  final String challengeId;
  final String status;
  final bool outgoing;
  final PublicUser opponent;
  final String? timeControlLabel;
  final String colorPreference;
  final String? gameId;
  final DateTime? expiresAt;

  const ChallengeModel({
    required this.challengeId,
    required this.status,
    required this.outgoing,
    required this.opponent,
    this.timeControlLabel,
    this.colorPreference = 'random',
    this.gameId,
    this.expiresAt,
  });

  bool get isPending => status == 'pending';

  bool get hasExpired {
    final deadline = expiresAt;
    return deadline != null && DateTime.now().toUtc().isAfter(deadline.toUtc());
  }

  factory ChallengeModel.fromJson(Map<String, dynamic> json) {
    final rawOpponent = json['opponent'];
    final rawTimeControl = json['time_control'];
    return ChallengeModel(
      challengeId: json['challenge_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      outgoing: json['outgoing'] == true,
      opponent: PublicUser.fromJson(
        rawOpponent is Map ? Map<String, dynamic>.from(rawOpponent) : const {},
      ),
      timeControlLabel:
          rawTimeControl is Map ? rawTimeControl['label']?.toString() : null,
      colorPreference: json['color_preference']?.toString() ?? 'random',
      gameId: json['game_id']?.toString(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
    );
  }
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}
