import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ble/robochess_ble.dart';
import '../providers/device_provider.dart';
import '../providers/session_provider.dart';

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
        final networkResponse = _ble.messages
            .firstWhere(
              (message) =>
                  message['type'] == 'control.result' &&
                  (message['data'] as Map?)?['status'] == 'network_status',
            )
            .timeout(const Duration(seconds: 8));
        await _ble.sendControl({
          'version': bleProtocolVersion,
          'request_id': DateTime.now().microsecondsSinceEpoch.toString(),
          'type': 'network.status',
          'device_id': deviceId,
          'data': const {},
        });
        final response = await networkResponse;
        final network = Map<String, dynamic>.from(
          ((response['data'] as Map)['network'] as Map?) ?? const {},
        );
        if (network['wifi_connected'] != true && mounted) {
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
      setState(() =>
          _message = 'Registering board and requesting secure credentials...');
      final credentials = await ref
          .read(deviceRepositoryProvider)
          .onboardingToken(deviceId: deviceId);
      if (credentials.deviceSecret == null) {
        throw StateError(
          'The backend did not return a device secret. Reset the board provisioning '
          'credentials and try again.',
        );
      }
      // Reconnect once more because the cloud request can outlive an iOS
      // BLE connection interval.
      await _ble.disconnect();
      await _ble.connectAndReadDeviceId(candidate.result.device);
      final claimResponse = _ble.messages.firstWhere((message) {
        if (message['type'] != 'control.result') return false;
        final status = (message['data'] as Map?)?['status'];
        return status == 'token_claimed' || status == 'error';
      }).timeout(const Duration(seconds: 15));
      await _ble.sendOnboardingToken(
        deviceId,
        credentials.onboardingToken,
        deviceSecret: credentials.deviceSecret,
      );
      if (_needsWifi == true) {
        setState(() => _message = 'Sending Wi-Fi credentials...');
        final wifiResponse = _ble.messages.firstWhere((message) {
          if (message['type'] != 'wifi.result') return false;
          return (message['data'] as Map?)?['status'] != null;
        }).timeout(const Duration(seconds: 30));
        await _ble.sendWifi(deviceId, _ssid.text.trim(), _password.text);
        final wifi = await wifiResponse;
        final wifiData =
            Map<String, dynamic>.from(wifi['data'] as Map? ?? const {});
        if (wifiData['status'] == 'error') {
          throw StateError(
              wifiData['error']?.toString() ?? 'Wi-Fi setup failed.');
        }
      }
      final claim = await claimResponse;
      final claimData =
          Map<String, dynamic>.from(claim['data'] as Map? ?? const {});
      if (claimData['status'] == 'error') {
        throw StateError(claimData['error']?.toString() ??
            'The board could not be linked to the cloud.');
      }
      setState(() => _message = 'Board linked. Refreshing linked boards...');
      await ref.read(deviceListProvider.notifier).load();
      if (mounted) {
        context.go('/connect');
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Cloud linking failed: $error');
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
