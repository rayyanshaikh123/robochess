import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/robochess_protocol.dart';

class LocalStateStore {
  static const _deviceKey = 'local_ble_device_id';
  static const _stateKey = 'local_pi_state';
  final FlutterSecureStorage storage;
  LocalStateStore({FlutterSecureStorage? storage}) : storage = storage ?? const FlutterSecureStorage();

  Future<void> saveDevice(String id) => storage.write(key: _deviceKey, value: id);
  Future<String?> loadDevice() => storage.read(key: _deviceKey);
  Future<void> saveState(PiState state) => storage.write(key: _stateKey, value: jsonEncode(state.toJson()));
  Future<PiState?> loadState() async {
    final raw = await storage.read(key: _stateKey);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return PiState(
      version: (data['version'] as num?)?.toInt() ?? 0,
      state: data['state']?.toString() ?? 'unknown',
      fen: data['fen']?.toString(),
      sessionId: data['session_id']?.toString(),
      lastMove: data['last_move']?.toString(),
      moveHistory: (data['move_history'] as List? ?? const []).map((e) => '$e').toList(),
      engineState: data['engine_state']?.toString(),
      motionState: data['motion_state']?.toString(),
      recoveryReason: data['reason']?.toString(),
    );
  }
}
