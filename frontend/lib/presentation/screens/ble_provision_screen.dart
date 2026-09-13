import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ble/robochess_ble.dart';
import '../providers/device_provider.dart';
import '../providers/local_board_provider.dart';

class BleProvisionScreen extends ConsumerStatefulWidget {
  const BleProvisionScreen({super.key});

  @override
  ConsumerState<BleProvisionScreen> createState() => _BleProvisionScreenState();
}

class _BleProvisionScreenState extends ConsumerState<BleProvisionScreen> {
  final _ble = RoboChessBleClient();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final _devices = <String, RoboChessBleDevice>{};
  String _message = 'Scan for nearby RoboChess boards.';
  bool _scanning = false;
  bool _working = false;
  bool? _needsWifi;
  String? _selectedRemoteId;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _ble.disconnect();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices.clear();
      _message = 'Scanning for RoboChess boards...';
    });
    await _scanSubscription?.cancel();
    _scanSubscription = _ble.scan().listen((results) {
      for (final result in results) {
        final item = RoboChessBleDevice(result);
        _devices[result.device.remoteId.str] = item;
      }
      if (mounted) setState(() {});
    }, onError: (Object error) {
      if (mounted) setState(() => _message = 'Bluetooth scan failed: $error');
    });
    await Future<void>.delayed(const Duration(seconds: 8));
    if (mounted) {
      setState(() {
        _scanning = false;
        if (_devices.isEmpty) {
          _message = 'No RoboChess boards found.';
        }
      });
    }
  }

  Future<void> _provision(RoboChessBleDevice candidate) async {
    setState(() {
      _working = true;
      _message = 'Connecting to ${candidate.name}...';
    });
    try {
      // iOS may silently drop the GATT connection while the Pi is checking
      // its network or while the app requests the cloud onboarding token.
      // Always rebuild the connection before sending the next command.
      await _ble.disconnect();
      final deviceId =
          await _ble.connectAndReadDeviceId(candidate.result.device);
      _selectedRemoteId = candidate.result.device.remoteId.str;
      if (_needsWifi != true) {
        setState(() => _message = 'Checking the board network...');
        final completer = Completer<Map<String, dynamic>>();
        late final StreamSubscription<Map<String, dynamic>> subscription;
        subscription = _ble.messages.listen((message) {
          if (message['type'] == 'control.result' &&
              (message['data'] as Map?)?['status'] == 'network_status') {
            if (!completer.isCompleted) {
              completer.complete(message);
            }
            subscription.cancel();
          }
        });

        await _ble.sendControl({
          'version': bleProtocolVersion,
          'request_id': DateTime.now().microsecondsSinceEpoch.toString(),
          'type': 'network.status',
          'device_id': deviceId,
          'data': const {},
        });

        final response = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            subscription.cancel();
            throw TimeoutException('Network status check timed out.');
          },
        );

        final network = Map<String, dynamic>.from(
          ((response['data'] as Map)['network'] as Map?) ?? const {},
        );
        ref.read(localBoardProvider.notifier).applyNetworkStatus(network);
        if ((network['wifi_connected'] != true ||
                network['internet_available'] != true) &&
            mounted) {
          setState(() {
            _needsWifi = true;
            _message =
                'Board is not connected to Wi-Fi. Enter its Wi-Fi credentials to link it.';
          });
          return;
        }
      }
      if (_needsWifi == true &&
          (_ssid.text.trim().isEmpty || _password.text.isEmpty)) {
        setState(
            () => _message = 'Enter the Wi-Fi network and password first.');
        return;
      }
      if (_needsWifi == true) {
        setState(() => _message = 'Sending Wi-Fi credentials to the Pi...');
        final completer = Completer<Map<String, dynamic>>();
        late final StreamSubscription<Map<String, dynamic>> subscription;
        subscription = _ble.messages.listen((message) {
          if (message['type'] == 'wifi.result' &&
              (message['data'] as Map?)?['status'] != null) {
            if (!completer.isCompleted) {
              completer.complete(message);
            }
            subscription.cancel();
          }
        });

        await _ble.sendWifi(deviceId, _ssid.text.trim(), _password.text);

        final wifi = await completer.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            subscription.cancel();
            throw TimeoutException('Wi-Fi setup timed out.');
          },
        );

        final wifiData =
            Map<String, dynamic>.from(wifi['data'] as Map? ?? const {});
        final wifiNetwork = wifiData['network'];
        if (wifiNetwork is Map) {
          ref.read(localBoardProvider.notifier).applyNetworkStatus(
                Map<String, dynamic>.from(wifiNetwork),
              );
        }
        if (wifiData['status'] == 'error') {
          throw StateError(
              wifiData['error']?.toString() ?? 'Wi-Fi setup failed.');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      setState(() => _message = 'Connecting to the Pi local setup...');
      await ref.read(localBoardProvider.notifier).adoptBoard(
            remoteId: candidate.result.device.remoteId.str,
            deviceId: deviceId,
          );
      await ref.read(localBoardProvider.notifier).refreshSetup();
      await ref.read(deviceListProvider.notifier).load();
      if (mounted) {
        setState(
            () => _message = 'Board connected locally. Opening Pi setup...');
        context.go('/connect/setup/$deviceId');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Local board setup failed: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _devices.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Set up RoboChess board')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_message),
          const SizedBox(height: 16),
          if (_needsWifi == true) ...[
            TextField(
                controller: _ssid,
                decoration:
                    const InputDecoration(labelText: 'Wi-Fi network (SSID)')),
            const SizedBox(height: 12),
            TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Wi-Fi password')),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: _scanning || _working ? null : _scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? 'SCANNING...' : 'SCAN NEARBY BOARDS'),
          ),
          const SizedBox(height: 16),
          for (final item in items)
            Card(
              child: ListTile(
                leading: const Icon(Icons.memory),
                title: Text(item.name),
                subtitle:
                    Text('ID: ${item.deviceId}\nSignal: ${item.rssi} dBm'),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: _working ? null : () => _provision(item),
                  child: Text(_needsWifi == true &&
                          _selectedRemoteId == item.result.device.remoteId.str
                      ? 'SEND WI-FI'
                      : 'CHECK STATUS'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
