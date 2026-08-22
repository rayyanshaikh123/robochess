import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const roboChessServiceUuid = '0000f00d-0000-1000-8000-00805f9b34fb';
const deviceInfoUuid = '0000f00e-0000-1000-8000-00805f9b34fb';
const controlUuid = '0000f00f-0000-1000-8000-00805f9b34fb';
const wifiUuid = '0000f010-0000-1000-8000-00805f9b34fb';
const statusUuid = '0000f011-0000-1000-8000-00805f9b34fb';
const bleProtocolVersion = '1';
const maxBleChunkBytes = 180;

class RoboChessBleDevice {
  final ScanResult result;
  RoboChessBleDevice(this.result);

  String get name => result.device.platformName.isNotEmpty
      ? result.device.platformName
      : 'RoboChess board';
  String get deviceId => result.advertisementData.serviceData.values
      .expand((bytes) => bytes)
      .isNotEmpty
      ? result.advertisementData.serviceData.values
          .expand((bytes) => bytes)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join()
      : result.device.remoteId.str;
  int get rssi => result.rssi;
}

class RoboChessBleClient {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _wifi;
  BluetoothCharacteristic? _status;
  StreamSubscription<List<int>>? _controlSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, List<List<int>>> _chunks = {};
  final Map<String, Timer> _chunkExpiry = {};
  Future<void> _writeQueue = Future<void>.value();

  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) async* {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      throw StateError('Bluetooth is disabled. Turn on Bluetooth and try again.');
    }
    await FlutterBluePlus.startScan(
      withServices: [Guid(roboChessServiceUuid)],
      timeout: timeout,
    );
    yield* FlutterBluePlus.scanResults;
  }

  Future<String> connectAndReadDeviceId(BluetoothDevice device) async {
    await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    // iOS owns the pairing UI; Android also bonds automatically on the first
    // authenticated write. Do not force a platform-specific bond dialog here.
    _device = device;
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (item) => item.uuid == Guid(roboChessServiceUuid),
      orElse: () => throw StateError('RoboChess BLE service not found'),
    );
    BluetoothCharacteristic find(String uuid) => service.characteristics.firstWhere(
          (item) => item.uuid == Guid(uuid),
          orElse: () => throw StateError('BLE characteristic not found: $uuid'),
        );
    final info = find(deviceInfoUuid);
    _control = find(controlUuid);
    _wifi = find(wifiUuid);
    _status = find(statusUuid);
    if (_control!.properties.notify) {
      await _control!.setNotifyValue(true);
      _controlSubscription = _control!.onValueReceived.listen(_handleFrame);
    }
    if (_status!.properties.notify) {
      await _status!.setNotifyValue(true);
      _statusSubscription = _status!.onValueReceived.listen(_handleFrame);
    }
    final bytes = await info.read();
    return utf8.decode(bytes, allowMalformed: true);
  }

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<String> get statusStream => messages.map(jsonEncode);

  void _handleFrame(List<int> bytes) {
    try {
      final frame = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (frame['t'] == 'chunk' && frame['v']?.toString() == bleProtocolVersion) {
        final id = frame['id']?.toString();
        final index = frame['i'];
        final total = frame['n'];
        final payload = frame['p'];
        if (id == null || index is! int || total is! int || payload is! String || index < 0 || index >= total) return;
        final chunks = _chunks.putIfAbsent(id, () => List<List<int>>.filled(total, const []));
        _chunkExpiry.putIfAbsent(id, () => Timer(const Duration(seconds: 10), () {
              _chunks.remove(id);
              _chunkExpiry.remove(id);
            }));
        if (chunks.length != total) {
          _chunks.remove(id);
          _chunkExpiry.remove(id)?.cancel();
          return;
        }
        chunks[index] = base64Decode(payload);
        if (chunks.every((item) => item.isNotEmpty)) {
          _chunks.remove(id);
          _chunkExpiry.remove(id)?.cancel();
          _messages.add(jsonDecode(utf8.decode(chunks.expand((item) => item).toList())) as Map<String, dynamic>);
        }
        return;
      }
      _messages.add(frame);
    } catch (_) {
      // Ignore malformed/partial notifications; caller can request state again.
    }
  }

  Future<void> sendOnboardingToken(String deviceId, String token) async {
    await _writeChunks(_control, {
      'version': bleProtocolVersion,
      'request_id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': 'onboarding.token',
      'device_id': deviceId,
      'data': {'onboarding_token': token},
    });
  }

  Future<void> sendWifi(String deviceId, String ssid, String password) async {
    await _writeChunks(_wifi, {
      'version': bleProtocolVersion,
      'request_id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': 'wifi.provision',
      'device_id': deviceId,
      'data': {'ssid': ssid, 'password': password},
    });
  }

  Future<void> sendControl(Map<String, dynamic> value) => _writeChunks(_control, value);

  Future<void> _writeChunks(BluetoothCharacteristic? characteristic, Map<String, dynamic> value) {
    // Keep commands ordered. This matters when a user submits the next move
    // while the previous command's state notification is still arriving.
    final operation = _writeQueue.then<void>(
      (_) => _writeChunksNow(characteristic, value),
      onError: (_, __) => _writeChunksNow(characteristic, value),
    );
    _writeQueue = operation;
    return operation;
  }

  Future<void> _writeChunksNow(BluetoothCharacteristic? characteristic, Map<String, dynamic> value) async {
    if (characteristic == null) throw StateError('BLE characteristic is unavailable');
    // BlueZ can expose the RoboChess secure-write characteristic as either
    // WRITE or WRITE WITHOUT RESPONSE, depending on the Android Bluetooth
    // stack.  Requesting a response unconditionally makes
    // flutter_blue_plus reject the latter *before* the message reaches Pi.
    final supportsWrite = characteristic.properties.write;
    final supportsWriteWithoutResponse = characteristic.properties.writeWithoutResponse;
    if (!supportsWrite && !supportsWriteWithoutResponse) {
      throw StateError(
        'BLE characteristic ${characteristic.uuid} is not writable. '
        'Reconnect to the RoboChess board and try again.',
      );
    }
    final withoutResponse = !supportsWrite && supportsWriteWithoutResponse;
    final bytes = utf8.encode(jsonEncode(value));
    for (var offset = 0; offset < bytes.length; offset += maxBleChunkBytes) {
      final end = math.min(offset + maxBleChunkBytes, bytes.length);
      await characteristic.write(
        bytes.sublist(offset, end),
        withoutResponse: withoutResponse,
      );
      if (withoutResponse && end < bytes.length) {
        // Without-response writes are not flow-controlled by the platform.
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    }
  }

  Future<void> disconnect() async {
    await _controlSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _device?.disconnect();
    _device = null;
    _control = null;
    _wifi = null;
    _status = null;
  }

  Future<void> dispose() async {
    await disconnect();
    for (final timer in _chunkExpiry.values) {
      timer.cancel();
    }
    _chunkExpiry.clear();
    _chunks.clear();
    await _messages.close();
  }
}
