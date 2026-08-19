import 'dart:async';
import 'dart:convert';

import '../datasources/ble_service.dart';
import '../../domain/models/robochess_device.dart';
import '../../domain/models/robochess_protocol.dart';

class LocalBoardRepository {
  final BleService ble;
  int _sequence = 0;
  int _lastPiVersion = -1;

  LocalBoardRepository(this.ble);

  Stream<RoboChessDevice> get discoveredDevices => ble.devices;
  Stream<List<int>> get notifications => ble.messages;
  Stream<List<int>> get statusNotifications => ble.statusMessages;

  Future<void> send(String type, [Map<String, dynamic> payload = const {}]) async {
    final command = ProtocolCommand(type, ++_sequence, payload);
    await ble.write(utf8.encode(command.toMessage().encode()));
  }

  RoboChessMessage parse(List<int> bytes) => RoboChessMessage.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );

  bool acceptState(PiState state) {
    if (state.version < _lastPiVersion) return false;
    _lastPiVersion = state.version;
    return true;
  }

  Future<void> startSession() => send('session.start');
  Future<void> requestState() => send('state.request');
  Future<void> resumeSession() => send('session.resume');
  Future<void> resetSession() => send('session.reset');
  Future<void> proposeMove(String move) => send('move.propose', {'move': move});
}
