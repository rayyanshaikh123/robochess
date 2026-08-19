import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/robochess_device.dart';

class BleService {
  final _devices = StreamController<RoboChessDevice>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _status;

  Stream<RoboChessDevice> get devices => _devices.stream;
  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;
  BluetoothDevice? get connectedDevice => _device;
  Stream<BluetoothConnectionState> get connectionState =>
      _device?.connectionState ?? const Stream.empty();

  Future<void> scan({Duration timeout = const Duration(seconds: 8)}) async {
    await stopScan();
    await FlutterBluePlus.startScan(
      withServices: [Guid(AppConfig.roboChessServiceUuid)],
      timeout: timeout,
    );
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertisement = result.advertisementData.serviceData;
        String? deviceId;
        for (final bytes in advertisement.values) {
          final value = utf8.decode(bytes, allowMalformed: true).trim();
          if (value.isNotEmpty && value.length < 80) deviceId = value;
        }
        _devices.add(RoboChessDevice(
          remoteId: result.device.remoteId.str,
          displayName: result.advertisementData.advName.isNotEmpty
              ? result.advertisementData.advName
              : result.device.platformName,
          deviceId: deviceId,
          rssi: result.rssi,
        ));
      }
    });
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (await FlutterBluePlus.isScanning.first) await FlutterBluePlus.stopScan();
  }

  Future<void> connect(RoboChessDevice board) async {
    final device = BluetoothDevice.fromId(board.remoteId);
    await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    _device = device;
    final services = await device.discoverServices();
    final service = services.firstWhere((s) => s.uuid == Guid(AppConfig.roboChessServiceUuid));
    _rx = _find(service, AppConfig.roboChessRxUuid);
    _tx = _find(service, AppConfig.roboChessTxUuid);
    _status = _find(service, AppConfig.roboChessStatusUuid);
    if (_tx != null) await _tx!.setNotifyValue(true);
    if (_status != null) await _status!.setNotifyValue(true);
  }

  BluetoothCharacteristic? _find(BluetoothService service, String uuid) {
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == Guid(uuid)) return characteristic;
    }
    return null;
  }

  Stream<List<int>> get messages => _tx?.onValueReceived ?? const Stream.empty();
  Stream<List<int>> get statusMessages => _status?.onValueReceived ?? const Stream.empty();

  Future<void> write(List<int> value) async {
    final characteristic = _rx;
    if (characteristic == null) throw StateError('BLE RX characteristic unavailable');
    await characteristic.write(value, withoutResponse: false);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _rx = null;
    _tx = null;
    _status = null;
  }

  void dispose() {
    _adapterSubscription?.cancel();
    _scanSubscription?.cancel();
    _devices.close();
  }
}
