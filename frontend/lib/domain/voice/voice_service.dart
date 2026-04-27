import 'dart:async';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

class MicInputDevice {
  final int id;
  final String name;
  final String type;
  final bool isSelected;

  const MicInputDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isSelected,
  });

  factory MicInputDevice.fromMap(Map<dynamic, dynamic> map) {
    return MicInputDevice(
      id: map['id'] as int? ?? -1,
      name: map['name'] as String? ?? 'Unknown microphone',
      type: map['type'] as String? ?? 'Unknown',
      isSelected: map['isSelected'] as bool? ?? false,
    );
  }
}

/// Port of VoiceModule/listener.py
///
/// Wraps [speech_to_text] to provide a clean API for continuous
/// voice listening with status callbacks.
class VoiceService {
  static const _audioChannel =
      MethodChannel('com.example.robochess_mobile/audio_input');
  static const _listenWindow = Duration(seconds: 60);
  static const _initialPauseWindow = Duration(seconds: 10);
  static const _restartDelay = Duration(milliseconds: 900);
  static const _quickNoMatchGracePeriod = Duration(seconds: 6);

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  DateTime? _listenStartedAt;
  Timer? _restartTimer;

  /// Stream controller for status messages (e.g. "Listening...", errors).
  final _statusController = StreamController<String>.broadcast();

  /// Stream controller for recognised speech text.
  final _resultController = StreamController<String>.broadcast();

  // ── Public getters ──────────────────────────────────────────────────────

  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized;

  /// Stream of status messages for the UI.
  Stream<String> get statusStream => _statusController.stream;

  /// Stream of recognised speech results.
  Stream<String> get resultStream => _resultController.stream;

  Future<List<MicInputDevice>> getAvailableMicrophones() async {
    try {
      final devices =
          await _audioChannel.invokeListMethod<dynamic>('getInputDevices') ??
              const [];
      return devices
          .whereType<Map<dynamic, dynamic>>()
          .map(MicInputDevice.fromMap)
          .toList();
    } on PlatformException catch (error) {
      _statusController.add('Mic list unavailable: ${error.message}');
      return const [];
    } on MissingPluginException {
      _statusController.add('Mic list unavailable on this platform');
      return const [];
    }
  }

  Future<bool> selectMicrophone(MicInputDevice device) async {
    final wasListening = _isListening;
    if (wasListening) {
      await stopListening();
    }

    try {
      final selected = await _audioChannel.invokeMethod<bool>(
            'selectInputDevice',
            {'id': device.id},
          ) ??
          false;

      _statusController.add(
        selected
            ? 'Microphone selected: ${device.name}'
            : 'Using system route for: ${device.name}',
      );
      return selected;
    } on PlatformException catch (error) {
      _statusController.add('Mic selection failed: ${error.message}');
      return false;
    } on MissingPluginException {
      _statusController.add('Mic selection unavailable on this platform');
      return false;
    } finally {
      if (wasListening) {
        await startListening();
      }
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Initialise the speech recogniser. Must be called before [startListening].
  /// Returns `true` if speech recognition is available on this device.
  Future<bool> initialize() async {
    _isInitialized = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
      debugLogging: false,
    );

    if (!_isInitialized) {
      _statusController.add('Speech recognition not available');
    }

    return _isInitialized;
  }

  /// Start listening for speech input.
  /// Recognised text is emitted on [resultStream].
  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    _isListening = true;
    if (_speech.isListening) {
      _statusController.add('Listening for your move...');
      return;
    }

    _restartTimer?.cancel();
    _listenStartedAt = DateTime.now();
    _statusController.add('Listening for your move...');

    await _speech.listen(
      onResult: _onResult,
      listenFor: _listenWindow,
      pauseFor: _initialPauseWindow,
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
    );
  }

  /// Stop listening.
  Future<void> stopListening() async {
    _isListening = false;
    _listenStartedAt = null;
    _restartTimer?.cancel();
    await _speech.stop();
    _statusController.add('Mic off');
  }

  /// Clean up resources.
  void dispose() {
    _restartTimer?.cancel();
    _speech.stop();
    _speech.cancel();
    _statusController.close();
    _resultController.close();
  }

  // ── Internal callbacks ──────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult && result.recognizedWords.isNotEmpty) {
      _statusController.add('Hearing: "${result.recognizedWords}"');
      return;
    }

    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      _resultController.add(result.recognizedWords);
      _statusController.add('Heard: "${result.recognizedWords}"');

      // Auto-restart if still in listening mode
      if (_isListening) {
        _scheduleRestart();
      }
    }
  }

  void _onStatus(String status) {
    if (status == 'done' && _isListening) {
      // Restart listening if the engine stopped but we're still active
      _statusController.add('Still listening...');
      _scheduleRestart();
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (error.errorMsg == 'error_no_match') {
      final elapsed = _listenStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_listenStartedAt!);

      if (elapsed < _quickNoMatchGracePeriod) {
        _statusController.add('Still listening...');
        if (_isListening) {
          _scheduleRestart();
        }
        return;
      }
    }

    if (error.errorMsg == 'error_no_match') {
      _statusController.add("Didn't catch that — try again");
      // Restart if still active
      if (_isListening) {
        _scheduleRestart();
      }
    } else if (error.errorMsg == 'error_speech_timeout') {
      _statusController.add('No speech detected — listening...');
      if (_isListening) {
        _scheduleRestart();
      }
    } else {
      _statusController.add('Error: ${error.errorMsg}');
    }
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartDelay, () {
      if (_isListening) startListening();
    });
  }
}
