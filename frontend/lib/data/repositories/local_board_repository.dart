import '../../core/ble/robochess_ble.dart';
import '../../domain/models/robochess_protocol.dart';

class LocalBoardRepository {
  final RoboChessBleClient ble;
  int _sequence = 0;
  int _lastPiVersion = -1;
  String? _deviceId;
  final Map<String, RoboChessBleDevice> _scanned = {};

  LocalBoardRepository(this.ble);

  Stream<Map<String, dynamic>> get notifications => ble.messages;
  Stream<RoboChessBleDevice> scan() => ble.scan().expand((items) => items.map(RoboChessBleDevice.new)).map((device) {
        _scanned[device.result.device.remoteId.str] = device;
        return device;
      });
  String? get deviceId => _deviceId;

  Future<String> connect(RoboChessBleDevice device) async {
    _deviceId = await ble.connectAndReadDeviceId(device.result.device);
    return _deviceId!;
  }

  Future<String> connectRemote(String remoteId) {
    final device = _scanned[remoteId];
    if (device == null) throw StateError('Board is no longer in scan results; scan again.');
    return connect(device);
  }

  Future<void> send(String type, [Map<String, dynamic> data = const {}]) async {
    final id = _deviceId;
    if (id == null) throw StateError('Connect to a board before sending commands');
    await ble.sendControl(RoboChessMessage(
      type: type,
      requestId: '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      deviceId: id,
      data: {...data, 'client_seq': _sequence},
    ).toJson());
  }

  RoboChessMessage parse(Map<String, dynamic> value) => RoboChessMessage.fromJson(value);

  bool acceptState(PiState state) {
    if (state.version < _lastPiVersion) return false;
    _lastPiVersion = state.version;
    return true;
  }

  Future<void> startSession() => send('session.start');
  Future<void> requestState() => send('state.request');
  Future<void> requestNetworkStatus() => send('network.status');
  Future<void> resumeSession() => send('session.resume');
  Future<void> resetSession() => send('session.reset');
  Future<void> homeGantry() => send('gantry.home');
  Future<void> gantryStatus() => send('gantry.status');
  Future<void> proposeMove(String move, int expectedVersion) => send('move.propose', {'uci': move, 'expected_version': expectedVersion});
  Future<void> provisionWifi(String ssid, String password) async {
    final id = _deviceId;
    if (id == null) throw StateError('Connect to a board before provisioning Wi-Fi');
    await ble.sendWifi(id, ssid, password);
  }
  Future<void> saveCameraCalibration({required int cameraIndex, required int rotation, required String boardOrientation}) =>
      send('camera.calibrate', {'camera_index': cameraIndex, 'rotation': rotation, 'board_orientation': boardOrientation});
}
