class PiSetupStage {
  final String key;
  final bool ok;
  final bool required;
  final String message;
  final Map<String, dynamic> details;

  const PiSetupStage({
    required this.key,
    required this.ok,
    required this.required,
    required this.message,
    this.details = const {},
  });

  factory PiSetupStage.fromJson(Map<String, dynamic> json) => PiSetupStage(
        key: json['key']?.toString() ?? '',
        ok: json['ok'] == true,
        required: json['required'] != false,
        message: json['message']?.toString() ?? '',
        details: Map<String, dynamic>.from(json['details'] as Map? ?? const {}),
      );
}

class PiSetupStatus {
  final bool ready;
  final String visionMode;
  final List<PiSetupStage> stages;
  final List<String> missing;

  const PiSetupStatus({
    required this.ready,
    required this.visionMode,
    required this.stages,
    required this.missing,
  });

  factory PiSetupStatus.fromJson(Map<String, dynamic> json) => PiSetupStatus(
        ready: json['ready'] == true,
        visionMode: json['vision_mode']?.toString() ?? 'unknown',
        stages: (json['stages'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                PiSetupStage.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        missing: (json['missing'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}
