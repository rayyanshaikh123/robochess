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
      // Always reconnect — iOS silently drops GATT during idle periods.
      await _ble.disconnect();
      final deviceId =
          await _ble.connectAndReadDeviceId(candidate.result.device);
      _selectedRemoteId = candidate.result.device.remoteId.str;

      if (_needsWifi != true) {
        // Read F011 status directly — BLE reads are reliable request/response,
        // unlike notifications which depend on bluezero's D-Bus delivery.
        setState(() => _message = 'Reading board status...');
        final status = await _ble.readStatus();
        final boardStatus =
            (status?['data'] as Map<String, dynamic>?)?['status']?.toString() ??
                '';
        final boardIp =
            (status?['data'] as Map<String, dynamic>?)?['ip_address']
                ?.toString();

        if (boardIp != null && boardIp.isNotEmpty) {
          // Update the local API URL if the Pi already has a known IP.
          ref.read(localBoardProvider.notifier).applyNetworkStatus({
            'wifi_connected': true,
            'internet_available': false,
            'ip_address': boardIp,
          });
        }

        if (boardStatus != 'wifi_connected') {
          setState(() {
            _needsWifi = true;
            _message =
                'Board is not connected to Wi-Fi. Enter credentials to link it.';
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
        await _ble.sendWifi(deviceId, _ssid.text.trim(), _password.text);

        // Poll F011 until the Pi reports wifi_connected or error.
        // BLE reads are reliable and avoid the bluezero notification issue.
        setState(() => _message = 'Connecting Pi to Wi-Fi (up to 30s)...');
        String wifiStatus = '';
        String? wifiIp;
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          final polled = await _ble.readStatus();
          final data = polled?['data'] as Map<String, dynamic>? ?? {};
          wifiStatus = data['status']?.toString() ?? '';
          wifiIp = data['ip_address']?.toString();
          if (wifiStatus == 'wifi_connected' || wifiStatus == 'error') break;
        }

        if (wifiStatus == 'error') {
          throw StateError('Wi-Fi connection failed. Check credentials.');
        }
        if (wifiStatus != 'wifi_connected') {
          throw TimeoutException(
              'Wi-Fi connection timed out.', const Duration(seconds: 30));
        }

        if (wifiIp != null && wifiIp.isNotEmpty) {
          ref.read(localBoardProvider.notifier).applyNetworkStatus({
            'wifi_connected': true,
            'internet_available': true,
            'ip_address': wifiIp,
          });
        }
      }

      setState(() => _message = 'Connecting to Pi local setup...');
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
