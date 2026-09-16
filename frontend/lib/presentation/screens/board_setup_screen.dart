import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/pi_setup.dart';
import '../../domain/models/robochess_device.dart';
import '../../domain/models/robochess_protocol.dart';
import '../providers/local_board_provider.dart';
import '../widgets/pi_live_camera_view.dart';

class BoardSetupScreen extends ConsumerStatefulWidget {
  final String deviceId;

  const BoardSetupScreen({super.key, required this.deviceId});

  @override
  ConsumerState<BoardSetupScreen> createState() => _BoardSetupScreenState();
}

class _BoardSetupScreenState extends ConsumerState<BoardSetupScreen> {
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localBoardProvider.notifier).refreshSetup();
      ref.read(localBoardProvider.notifier).refreshNetworkStatus();
      _poller = Timer.periodic(
        const Duration(seconds: 4),
        (_) {
          ref.read(localBoardProvider.notifier).refreshSetup();
          ref.read(localBoardProvider.notifier).refreshNetworkStatus();
        },
      );
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localBoardProvider);
    final setup = state.setup;
    final baseUrl = state.localApiBaseUrl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up board'),
        actions: [
          IconButton(
            onPressed: state.setupLoading
                ? null
                : () => ref.read(localBoardProvider.notifier).refreshSetup(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Board ${widget.deviceId}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            baseUrl == null
                ? 'Waiting for the Pi LAN address'
                : 'Pi local API: $baseUrl',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _PiDiagnostics(
            network: state.network,
            setup: setup,
            connection: state.connection,
          ),
          const SizedBox(height: 16),
          if (baseUrl != null) PiLiveCameraView(baseUrl: baseUrl),
          const SizedBox(height: 16),
          if (setup == null)
            const Card(child: ListTile(title: Text('Checking Pi setup…')))
          else
            ...setup.stages.map((stage) => _StageTile(stage: stage)),
          if ((state.network?.wifiConnected != true && state.network?.ipAddress == null) &&
              (state.network == null || !state.network!.internetAvailable)) ...[
            const SizedBox(height: 12),
            _WifiProvisioningPanel(networks: state.wifiNetworks),
          ],
          const SizedBox(height: 12),
          _ActionButton(
            label: 'LOAD ROBOFLOW DETECTOR',
            enabled: _missing(setup, 'roboflow_ready'),
            loading: state.setupLoading,
            onPressed: () =>
                ref.read(localBoardProvider.notifier).loadPiModel(),
          ),
          _ActionButton(
            label: 'AUTO-CALIBRATE BOARD',
            enabled: _missing(setup, 'calibrated'),
            loading: state.setupLoading,
            onPressed: () =>
                ref.read(localBoardProvider.notifier).autoCalibrate(),
          ),
          _ActionButton(
            label: 'ENTER CALIBRATION CORNERS',
            enabled: _missing(setup, 'calibrated'),
            loading: state.setupLoading,
            onPressed: () => _manualCalibration(context),
          ),
          _ActionButton(
            label: 'VALIDATE STARTING POSITION',
            enabled: _missing(setup, 'starting_position_valid'),
            loading: state.setupLoading,
            onPressed: () => ref
                .read(localBoardProvider.notifier)
                .validateStartingPosition(),
          ),
          _ActionButton(
            label: 'HOME GANTRY',
            enabled: _missing(setup, 'gantry_homed'),
            loading: state.setupLoading,
            onPressed: () =>
                ref.read(localBoardProvider.notifier).homePiGantry(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: setup?.ready == true && !state.setupLoading
                ? () async {
                    await ref.read(localBoardProvider.notifier).confirmSetup();
                    if (!context.mounted) return;
                    context.go('/play');
                  }
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('READY — PLAY CHESS'),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }

  bool _missing(PiSetupStatus? setup, String key) {
    if (setup == null) return false;
    return setup.missing.contains(key);
  }

  Future<void> _manualCalibration(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controllers = List.generate(8, (_) => TextEditingController());
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Board corners'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Enter x,y for TL, TR, BR, BL from the Pi camera frame.'),
                for (var index = 0; index < 4; index++)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controllers[index * 2],
                          keyboardType: TextInputType.number,
                          decoration:
                              InputDecoration(labelText: 'P${index + 1} X'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controllers[index * 2 + 1],
                          keyboardType: TextInputType.number,
                          decoration:
                              InputDecoration(labelText: 'P${index + 1} Y'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('SAVE'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final values = controllers
          .map((controller) => double.tryParse(controller.text.trim()))
          .toList();
      if (values.any((value) => value == null)) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('Enter numeric coordinates for all four corners.')),
        );
        return;
      }
      final corners = List.generate(
        4,
        (index) => [values[index * 2]!, values[index * 2 + 1]!],
      );
      await ref.read(localBoardProvider.notifier).manualCalibrate(corners);
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }
}

class _PiDiagnostics extends StatelessWidget {
  final PiNetworkStatus? network;
  final PiSetupStatus? setup;
  final LocalConnectionState connection;

  const _PiDiagnostics({
    required this.network,
    required this.setup,
    required this.connection,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = connection == LocalConnectionState.connected ||
        connection == LocalConnectionState.ready;
    final isWifiOk =
        network?.wifiConnected == true || (network?.ipAddress != null);
    final rows = <Widget>[
      _DiagnosticRow(
        'Board Link',
        connection != LocalConnectionState.disconnected,
        isConnected ? 'Connected' : connection.name,
      ),
      _DiagnosticRow(
        'Wi-Fi',
        isWifiOk,
        network?.ssid != null
            ? network!.ssid!
            : (network?.ipAddress != null
                ? 'Connected (${network!.ipAddress})'
                : 'Not connected'),
      ),
      _DiagnosticRow(
        'Internet',
        network?.internetAvailable == true,
        network?.internetAvailable == true
            ? 'Online'
            : (network?.state ?? 'Checking'),
      ),
      _DiagnosticRow(
        'Backend',
        network?.backendAvailable == true,
        network?.backendAvailable == true ? 'Connected' : 'Local Mode',
      ),
      _DiagnosticRow(
        'Pi local API',
        network?.localServiceAvailable != false,
        network?.ipAddress ?? '192.168.0.219:8765',
      ),
      _DiagnosticRow(
        'Board setup',
        setup?.ready == true,
        setup == null
            ? 'Checking'
            : (setup?.ready == true
                ? 'Ready to Play'
                : 'Calibration / Model needed'),
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PI STATUS', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String detail;

  const _DiagnosticRow(this.label, this.ok, this.detail);

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(ok ? Icons.check_circle : Icons.cancel,
            color: ok ? Colors.green : Colors.orange),
        title: Text(label),
        trailing: Text(detail, textAlign: TextAlign.right),
      );
}

class _WifiProvisioningPanel extends ConsumerStatefulWidget {
  final List<PiWifiNetwork> networks;

  const _WifiProvisioningPanel({required this.networks});

  @override
  ConsumerState<_WifiProvisioningPanel> createState() =>
      _WifiProvisioningPanelState();
}

class _WifiProvisioningPanelState
    extends ConsumerState<_WifiProvisioningPanel> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _sending = false;
  bool _scanning = false;
  String? _selectedSsid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ssid = _selectedSsid ?? _ssid.text.trim();
    if (ssid.isEmpty || _password.text.isEmpty) return;
    setState(() => _sending = true);
    await ref.read(localBoardProvider.notifier).provisionWifi(
          ssid,
          _password.text,
        );
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    await ref.read(localBoardProvider.notifier).scanWifiNetworks();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.35),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PI INTERNET UNAVAILABLE',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('Send Wi-Fi credentials securely over Bluetooth.'),
              Row(
                children: [
                  Expanded(
                    child: widget.networks.isEmpty
                        ? TextField(
                            controller: _ssid,
                            decoration:
                                const InputDecoration(labelText: 'Wi-Fi name'),
                          )
                        : DropdownButtonFormField<String>(
                            value: _selectedSsid,
                            decoration:
                                const InputDecoration(labelText: 'Wi-Fi name'),
                            items: widget.networks
                                .map((network) => DropdownMenuItem(
                                      value: network.ssid,
                                      child: Text(
                                          '${network.ssid} (${network.signal}%)'),
                                    ))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedSsid = value),
                          ),
                  ),
                  IconButton(
                    tooltip: 'Scan nearby networks',
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Wi-Fi password'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.wifi),
                label: Text(_sending ? 'SENDING...' : 'PROVISION PI WI-FI'),
              ),
            ],
          ),
        ),
      );
}

class _StageTile extends StatelessWidget {
  final PiSetupStage stage;

  const _StageTile({required this.stage});

  @override
  Widget build(BuildContext context) {
    final color = stage.ok ? Colors.green : Colors.orange;
    return Card(
      child: ListTile(
        leading:
            Icon(stage.ok ? Icons.check_circle : Icons.pending, color: color),
        title: Text(stage.key.replaceAll('_', ' ').toUpperCase()),
        subtitle: Text(stage.message),
        trailing: Text(stage.required ? 'REQUIRED' : 'OPTIONAL'),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton(
          onPressed: enabled && !loading ? onPressed : null,
          child: Text(label),
        ),
      );
}
