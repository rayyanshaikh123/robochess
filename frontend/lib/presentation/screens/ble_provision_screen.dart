import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ble/robochess_ble.dart';
import '../../domain/models/robochess_protocol.dart';
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
  Timer? _statusTimer;
  final _devices = <String, RoboChessBleDevice>{};
  String _message = 'Scan for a nearby RoboChess board.';
  bool _scanning = false;
  bool _working = false;
  bool _manualNetwork = false;
  String? _connectedDeviceId;
  String? _selectedSsid;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _statusTimer?.cancel();
    _ble.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connectLan() async {
    setState(() {
      _working = true;
      _message = 'Connecting to Pi over local Wi-Fi...';
    });
    try {
      final id = await ref.read(localBoardProvider.notifier).connectLocalApi();
      if (mounted) context.go('/connect/setup/${Uri.encodeComponent(id)}');
    } catch (error) {
      if (mounted) setState(() => _message = 'Wi-Fi connection failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
      if (mounted) {
        setState(() {
          _scanning = false;
          _message = 'Bluetooth scan failed: $error';
        });
      }
    });
    await Future<void>.delayed(const Duration(seconds: 8));
    if (mounted) {
      setState(() {
        _scanning = false;
        if (_devices.isEmpty) _message = 'No RoboChess boards found.';
      });
    }
  }

  Future<void> _connectBoard(RoboChessBleDevice candidate) async {
    setState(() {
      _working = true;
      _message = 'Connecting to ${candidate.name} over Bluetooth...';
    });
    try {
      final id = await ref
          .read(localBoardProvider.notifier)
          .connectBluetoothDevice(candidate);
      _connectedDeviceId = id;
      if (mounted) {
        setState(
            () => _message = 'Connected. Scanning Wi-Fi networks on the Pi...');
      }
      await _scanWifiNetworks();
      _startStatusPolling();
    } catch (error) {
      if (mounted)
        setState(() => _message = 'Bluetooth connection failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _scanWifiNetworks() async {
    if (_working && _connectedDeviceId == null) return;
    await ref.read(localBoardProvider.notifier).scanWifiNetworks();
    if (!mounted) return;
    final state = ref.read(localBoardProvider);
    setState(() {
      _message = state.wifiProvisioning == WifiProvisioningState.error
          ? (state.wifiProvisioningError ?? 'Wi-Fi scan failed.')
          : 'Select the Wi-Fi network the Pi should use.';
    });
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final state = ref.read(localBoardProvider);
      if (state.wifiProvisioning == WifiProvisioningState.connected) return;
      await ref.read(localBoardProvider.notifier).refreshBleStatus();
    });
  }

  Future<void> _provision() async {
    final local = ref.read(localBoardProvider);
    final network = local.wifiNetworks.cast<PiWifiNetwork?>().firstWhere(
          (item) => item?.ssid == _selectedSsid,
          orElse: () => null,
        );
    final ssid = _manualNetwork ? _ssid.text.trim() : network?.ssid ?? '';
    final security = network?.security.trim().toLowerCase();
    final isOpen = security == null ||
        security.isEmpty ||
        security == 'open' ||
        security == '--' ||
        security == 'none';
    if (ssid.isEmpty || (!isOpen && _password.text.isEmpty)) {
      setState(() => _message = isOpen
          ? 'Select a Wi-Fi network.'
          : 'Enter the Wi-Fi password to continue.');
      return;
    }

    setState(() {
      _working = true;
      _message = 'Sending Wi-Fi credentials securely to the Pi...';
    });
    await ref.read(localBoardProvider.notifier).provisionWifi(
          ssid,
          _password.text,
        );
    if (mounted) {
      final next = ref.read(localBoardProvider);
      setState(() {
        _working = false;
        _message = next.wifiProvisioning == WifiProvisioningState.error
            ? (next.wifiProvisioningError ?? 'Wi-Fi provisioning failed.')
            : 'Pi is connecting to $ssid...';
      });
    }
  }

  Future<void> _continueToSetup() async {
    final local = ref.read(localBoardProvider);
    final id = _connectedDeviceId ?? local.selected?.deviceId;
    if (id == null || local.localApiBaseUrl == null) return;
    setState(() {
      _working = true;
      _message = 'Checking the Pi setup service...';
    });
    try {
      await ref.read(localBoardProvider.notifier).refreshSetup();
      final next = ref.read(localBoardProvider);
      if (next.setup == null) {
        throw StateError('Pi setup service did not respond');
      }
      if (mounted) context.go('/connect/setup/${Uri.encodeComponent(id)}');
    } catch (error) {
      if (mounted)
        setState(() => _message = 'Pi setup is not reachable yet: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localBoardProvider);
    final items = _devices.values.toList();
    final connected = _connectedDeviceId != null;
    final wifiConnected =
        local.wifiProvisioning == WifiProvisioningState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Set up RoboChess board')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_message),
          const SizedBox(height: 16),
          if (!connected) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Connect over local Wi-Fi'),
                subtitle: const Text(
                    'Use this when the Pi is already on the same network.'),
                trailing: FilledButton.tonal(
                  onPressed: _working ? null : _connectLan,
                  child: const Text('CONNECT'),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                    onPressed: _working ? null : () => _connectBoard(item),
                    child: const Text('CONNECT'),
                  ),
                ),
              ),
          ] else ...[
            _ConnectionCard(local: local),
            const SizedBox(height: 16),
            _WifiNetworkPicker(
              networks: local.wifiNetworks,
              selectedSsid: _selectedSsid,
              manualNetwork: _manualNetwork,
              ssidController: _ssid,
              passwordController: _password,
              provisioning: local.wifiProvisioning,
              onScan: _working ? null : _scanWifiNetworks,
              onSelect: (ssid) => setState(() {
                _selectedSsid = ssid;
                _manualNetwork = false;
              }),
              onManual: () => setState(() {
                _manualNetwork = !_manualNetwork;
                _selectedSsid = null;
              }),
            ),
            const SizedBox(height: 12),
            if (!wifiConnected)
              FilledButton.icon(
                onPressed: _working ||
                        local.wifiProvisioning == WifiProvisioningState.scanning
                    ? null
                    : _provision,
                icon: const Icon(Icons.wifi),
                label: Text(_working ? 'CONNECTING...' : 'CONNECT PI TO WI-FI'),
              ),
            if (wifiConnected) ...[
              Card(
                color: Colors.green.withValues(alpha: 0.12),
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(
                      'Connected to ${local.provisionedSsid ?? local.network?.ssid ?? 'Wi-Fi'}'),
                  subtitle: Text(
                      local.localApiBaseUrl ?? 'Waiting for Pi IP address'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _working ? null : _continueToSetup,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('CONTINUE TO BOARD SETUP'),
              ),
            ],
            if (local.wifiProvisioningError != null) ...[
              const SizedBox(height: 12),
              Text(local.wifiProvisioningError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final LocalBoardState local;

  const _ConnectionCard({required this.local});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth_connected, color: Colors.blue),
        title: Text(local.selected?.displayName ?? 'RoboChess Pi connected'),
        subtitle: Text(
            'Bluetooth link active • ${local.selected?.deviceId ?? 'device ready'}'),
        trailing: const Icon(Icons.check_circle, color: Colors.green),
      ),
    );
  }
}

class _WifiNetworkPicker extends StatelessWidget {
  final List<PiWifiNetwork> networks;
  final String? selectedSsid;
  final bool manualNetwork;
  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final WifiProvisioningState provisioning;
  final VoidCallback? onScan;
  final ValueChanged<String> onSelect;
  final VoidCallback onManual;

  const _WifiNetworkPicker({
    required this.networks,
    required this.selectedSsid,
    required this.manualNetwork,
    required this.ssidController,
    required this.passwordController,
    required this.provisioning,
    required this.onScan,
    required this.onSelect,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        networks.where((item) => item.ssid == selectedSsid).firstOrNull;
    final selectedSecurity = selected?.security.trim().toLowerCase();
    final requiresPassword = manualNetwork ||
        (selectedSecurity != null &&
            selectedSecurity.isNotEmpty &&
            selectedSecurity != 'open' &&
            selectedSecurity != '--' &&
            selectedSecurity != 'none');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Wi-Fi networks on the Pi',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Scan nearby Wi-Fi networks',
                  onPressed: onScan,
                  icon: provisioning == WifiProvisioningState.scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (networks.isEmpty && !manualNetwork)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'No networks returned yet. Scan again or enter a hidden network.'),
              ),
            if (!manualNetwork)
              ...networks.map(
                (network) => RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: network.ssid,
                  groupValue: selectedSsid,
                  onChanged: (value) {
                    if (value != null) onSelect(value);
                  },
                  title: Text(network.ssid),
                  subtitle:
                      Text('${network.security} • ${network.signal}% signal'),
                  secondary: Icon(
                    network.signal >= 65
                        ? Icons.wifi
                        : network.signal >= 35
                            ? Icons.wifi_2_bar
                            : Icons.wifi_1_bar,
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: onManual,
              icon: Icon(manualNetwork ? Icons.list : Icons.edit),
              label: Text(
                  manualNetwork ? 'SELECT FROM SCAN' : 'USE HIDDEN NETWORK'),
            ),
            if (manualNetwork)
              TextField(
                controller: ssidController,
                decoration:
                    const InputDecoration(labelText: 'Network name (SSID)'),
              ),
            if (selectedSsid != null || manualNetwork) ...[
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: requiresPassword
                      ? 'Wi-Fi password'
                      : 'Password (not required)',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
