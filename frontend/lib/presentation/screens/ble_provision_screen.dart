import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  StreamSubscription<String>? _statusSubscription;
  final _devices = <String, RoboChessBleDevice>{};
  String _message = 'Scan for nearby RoboChess boards.';
  bool _scanning = false;
  bool _working = false;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _statusSubscription?.cancel();
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
    if (_ssid.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Enter the Wi-Fi network and password first.');
      return;
    }
    setState(() {
      _working = true;
      _message = 'Connecting to ${candidate.name}...';
    });
    try {
      final deviceId = await _ble.connectAndReadDeviceId(candidate.result.device);
      setState(() => _message = 'Requesting secure onboarding token...');
      final token = await ref.read(deviceRepositoryProvider).onboardingToken(deviceId: deviceId);
      await _ble.sendOnboardingToken(deviceId, token);
      setState(() => _message = 'Sending Wi-Fi credentials...');
      await _ble.sendWifi(deviceId, _ssid.text.trim(), _password.text);
      _statusSubscription = _ble.statusStream.listen((status) {
        if (mounted) setState(() => _message = status);
      });
      await ref.read(deviceListProvider.notifier).load();
      if (mounted) setState(() => _message = 'Provisioning started. The board will appear online when connected.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Provisioning failed: $error');
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
          TextField(controller: _ssid, decoration: const InputDecoration(labelText: 'Wi-Fi network (SSID)')),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Wi-Fi password')),
          const SizedBox(height: 16),
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
                subtitle: Text('ID: ${item.deviceId}\nSignal: ${item.rssi} dBm'),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: _working ? null : () => _provision(item),
                  child: const Text('SET UP'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
