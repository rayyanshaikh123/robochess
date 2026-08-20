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
  StreamSubscription<List<int>>? _statusSubscription;

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
    try {
      await device.createBond();
    } catch (_) {
      // Some Android devices bond automatically during the first secure write.
    }
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
    if (_status!.properties.notify) {
      await _status!.setNotifyValue(true);
    }
    final bytes = await info.read();
    return utf8.decode(bytes, allowMalformed: true);
  }

  Stream<String> get statusStream => _status == null
      ? const Stream.empty()
      : _status!.lastValueStream.map((bytes) => utf8.decode(bytes, allowMalformed: true));

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

  Future<void> _writeChunks(BluetoothCharacteristic? characteristic, Map<String, dynamic> value) async {
    if (characteristic == null) throw StateError('BLE characteristic is unavailable');
    final bytes = utf8.encode(jsonEncode(value));
    for (var offset = 0; offset < bytes.length; offset += maxBleChunkBytes) {
      final end = math.min(offset + maxBleChunkBytes, bytes.length);
      await characteristic.write(bytes.sublist(offset, end), withoutResponse: false);
    }
  }

  Future<void> disconnect() async {
    await _statusSubscription?.cancel();
    await _device?.disconnect();
    _device = null;
    _control = null;
    _wifi = null;
    _status = null;
  }
}
