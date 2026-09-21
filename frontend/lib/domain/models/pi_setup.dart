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

enum PiGamePhase {
  boot,
  initializing,
  ready,
  waitingForMove,
  detecting,
  validating,
  thinking,
  moving,
  verifying,
  error,
  calibrating,
  emergencyStop,
  disconnected,
  stateMismatch,
  cameraError,
  motorError,
  hardwareError,
  unknown;

  static PiGamePhase fromString(String phase) {
    switch (phase.toLowerCase()) {
      case 'boot':
        return PiGamePhase.boot;
      case 'initializing':
        return PiGamePhase.initializing;
      case 'ready':
        return PiGamePhase.ready;
      case 'waiting_for_move':
      case 'waitingformove':
        return PiGamePhase.waitingForMove;
      case 'detecting':
        return PiGamePhase.detecting;
      case 'validating':
        return PiGamePhase.validating;
      case 'thinking':
        return PiGamePhase.thinking;
      case 'moving':
      case 'executing_engine_move':
      case 'engine moving':
      case 'engine_moving':
        return PiGamePhase.moving;
      case 'verifying':
        return PiGamePhase.verifying;
      case 'error':
        return PiGamePhase.error;
      case 'calibrating':
        return PiGamePhase.calibrating;
      case 'emergency_stop':
      case 'emergencystop':
        return PiGamePhase.emergencyStop;
      case 'disconnected':
        return PiGamePhase.disconnected;
      case 'state_mismatch':
      case 'statemismatch':
        return PiGamePhase.stateMismatch;
      case 'camera_error':
      case 'cameraerror':
        return PiGamePhase.cameraError;
      case 'motor_error':
      case 'motorerror':
        return PiGamePhase.motorError;
      case 'hardware_error':
      case 'hardwareerror':
        return PiGamePhase.hardwareError;
      default:
        return PiGamePhase.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case PiGamePhase.boot:
        return 'Booting...';
      case PiGamePhase.initializing:
        return 'Initializing...';
      case PiGamePhase.ready:
        return 'Ready';
      case PiGamePhase.waitingForMove:
        return 'Waiting for Move';
      case PiGamePhase.detecting:
        return 'Detecting Move...';
      case PiGamePhase.validating:
        return 'Validating Board...';
      case PiGamePhase.thinking:
        return 'Engine Thinking...';
      case PiGamePhase.moving:
        return 'Moving Piece...';
      case PiGamePhase.verifying:
        return 'Verifying Board...';
      case PiGamePhase.error:
        return 'Error';
      case PiGamePhase.calibrating:
        return 'Calibrating...';
      case PiGamePhase.emergencyStop:
        return 'Emergency Stop';
      case PiGamePhase.disconnected:
        return 'Disconnected';
      case PiGamePhase.stateMismatch:
        return 'State Mismatch';
      case PiGamePhase.cameraError:
        return 'Camera Error';
      case PiGamePhase.motorError:
        return 'Motor Error';
      case PiGamePhase.hardwareError:
        return 'Hardware Error';
      case PiGamePhase.unknown:
        return 'Unknown';
    }
  }

  bool get isHumanTurnPhase => this == PiGamePhase.waitingForMove;
  bool get isEngineTurnPhase => this == PiGamePhase.thinking || this == PiGamePhase.moving || this == PiGamePhase.verifying;
  bool get isErrorPhase => this == PiGamePhase.error || this == PiGamePhase.emergencyStop || this == PiGamePhase.cameraError || this == PiGamePhase.motorError || this == PiGamePhase.hardwareError;
  bool get isDisconnectedPhase => this == PiGamePhase.disconnected;
}
