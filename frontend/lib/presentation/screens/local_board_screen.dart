import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../data/repositories/pi_local_api.dart';
import '../widgets/pi_live_camera_view.dart';
import '../../domain/models/robochess_device.dart';
import '../providers/local_board_provider.dart';

class LocalBoardScreen extends ConsumerWidget {
  const LocalBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localBoardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Local RoboChess')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: local.selected == null
            ? _ScanView(state: local)
            : _SessionView(state: local),
      ),
    );
  }
}

class _ScanView extends ConsumerWidget {
  final LocalBoardState state;
  const _ScanView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Nearby RoboChess Boards',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
          'Local mode works over Bluetooth and does not require Internet or backend access.'),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: state.scanning
            ? null
            : () => ref.read(localBoardProvider.notifier).scan(),
        icon: const Icon(Icons.bluetooth_searching),
        label: Text(state.scanning ? 'SCANNING...' : 'FIND NEARBY BOARDS'),
      ),
      if (state.error != null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20),
      Expanded(
          child: ListView(
              children: state.devices
                  .map((device) => _DeviceTile(device: device))
                  .toList())),
    ]);
  }
}

class _DeviceTile extends ConsumerWidget {
  final RoboChessDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        child: ListTile(
          leading: const Icon(Icons.grid_on),
          title: Text(device.displayName.isEmpty
              ? 'RoboChess board'
              : device.displayName),
          subtitle: Text(
              '${device.deviceId ?? 'Device ID pending'}  •  RSSI ${device.rssi} dBm'),
          trailing: FilledButton(
              onPressed: () =>
                  ref.read(localBoardProvider.notifier).connect(device),
              child: const Text('CONNECT')),
        ),
      );
}

class _SessionView extends ConsumerWidget {
  final LocalBoardState state;
  const _SessionView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pi = state.piState;
    return ListView(children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(state.selected?.displayName ?? 'RoboChess board'),
        subtitle: Text(
            '${state.connection.name}  •  ${state.selected?.deviceId ?? state.selected?.remoteId}'),
        trailing: Icon(Icons.circle,
            size: 12,
            color: state.connection == LocalConnectionState.ready
                ? Colors.green
                : Colors.orange),
      ),
      if (state.network != null)
        Card(
          child: ListTile(
            leading: Icon(
              state.network!.internetAvailable
                  ? Icons.cloud_done
                  : Icons.cloud_off,
              color: state.network!.internetAvailable
                  ? Colors.green
                  : Colors.orange,
            ),
            title: Text(state.network!.internetAvailable
                ? 'Board has internet'
                : 'Board is offline/local-only'),
            subtitle: Text(
              '${state.network!.state} • ${state.network!.ssid ?? 'No Wi-Fi'}'
              '${state.localApiBaseUrl == null ? '' : '\n${state.localApiBaseUrl}'}',
            ),
          ),
        ),
      const Divider(),
      const Text('Board Command Dashboard',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
          'Commands are sent directly to the Pi. Watch the Pi terminal for “BLE control received”.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: () =>
                ref.read(localBoardProvider.notifier).confirmSetup(),
            icon: const Icon(Icons.smart_toy),
            label: const Text('START BOT GAME')),
        OutlinedButton(
            onPressed: () => ref.read(localBoardProvider.notifier).reset(),
            child: const Text('RESET')),
        OutlinedButton(
            onPressed: () => ref.read(localBoardProvider.notifier).undo(),
            child: const Text('UNDO TURN')),
      ]),
      const SizedBox(height: 16),
      if (pi != null) ...[
        if (pi.fen != null) ChessPosition(fen: pi.fen!),
        const SizedBox(height: 12),
        Text('State: ${pi.state}'),
        Text('Version: ${pi.version}'),
        if (pi.lastMove != null) Text('Last move: ${pi.lastMove}'),
        const SizedBox(height: 12),
        if (state.connection == LocalConnectionState.recovering)
          const Text(
              'Physical board recovery is required. Reset or resume only after confirming the board position.'),
        MoveProposal(
            onSubmit: (move) =>
                ref.read(localBoardProvider.notifier).proposeMove(move)),
      ],
      const SizedBox(height: 16),
      MoveProposal(
          onSubmit: (move) =>
              ref.read(localBoardProvider.notifier).proposeMove(move)),
      const SizedBox(height: 24),
      if (state.network == null || !state.network!.internetAvailable)
        const _WifiPanel(),
      const SizedBox(height: 24),
      if (state.localApiBaseUrl != null)
        PiLiveCameraView(baseUrl: state.localApiBaseUrl!),
      const _CameraCalibrationPanel(),
      if (state.error != null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]);
  }
}

class _LiveCameraView extends StatefulWidget {
  final String baseUrl;
  const _LiveCameraView({required this.baseUrl});

  @override
  State<_LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends State<_LiveCameraView> {
  late PiLocalApi _api;
  Timer? _timer;
  Uint8List? _frame;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _api = PiLocalApi(baseUrl: widget.baseUrl);
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant _LiveCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) {
      _timer?.cancel();
      _api = PiLocalApi(baseUrl: widget.baseUrl);
      _frame = null;
      _startPolling();
    }
  }

  void _startPolling() {
    _loadFrame();
    _timer =
        Timer.periodic(const Duration(milliseconds: 400), (_) => _loadFrame());
  }

  Future<void> _loadFrame() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      Uint8List frame;
      try {
        frame = await _api.cameraFrame(preview: true);
      } catch (_) {
        // If BLE reports a stale/non-routable address, retry the configured
        // Pi address before showing an error. This is useful during hotspot
        // changes where NetworkManager may briefly report 127.0.0.1.
        if (_api.baseUrl == AppConfig.piLocalApiBaseUrl) rethrow;
        final fallback = PiLocalApi(baseUrl: AppConfig.piLocalApiBaseUrl);
        try {
          frame = await fallback.cameraFrame(preview: true);
        } finally {
          fallback.client.close();
        }
      }
      if (mounted)
        setState(() {
          _frame = frame;
          _error = null;
        });
    } catch (error) {
      if (mounted && _frame == null) {
        setState(() =>
            _error = 'Pi camera unavailable at ${widget.baseUrl}: $error');
      }
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api.client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: const Icon(Icons.videocam),
          title: const Text('Live board view'),
          subtitle: Text('Pi camera • ${widget.baseUrl}'),
          trailing: IconButton(
              onPressed: _loadFrame, icon: const Icon(Icons.refresh)),
        ),
        AspectRatio(
          aspectRatio: 1,
          child: _frame != null
              ? Image.memory(_frame!, fit: BoxFit.cover, gaplessPlayback: true)
              : Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, textAlign: TextAlign.center),
                        )),
        ),
        if (_error != null && _frame != null)
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _WifiPanel extends ConsumerStatefulWidget {
  const _WifiPanel();
  @override
  ConsumerState<_WifiPanel> createState() => _WifiPanelState();
}

class _WifiPanelState extends ConsumerState<_WifiPanel> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Wi-Fi provisioning',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: _ssid,
                decoration:
                    const InputDecoration(labelText: 'Wi-Fi name (SSID)')),
            TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Wi-Fi password')),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: () => ref
                    .read(localBoardProvider.notifier)
                    .provisionWifi(_ssid.text.trim(), _password.text),
                child: const Text('SEND TO PI')),
          ])));
}

class _CameraCalibrationPanel extends ConsumerStatefulWidget {
  const _CameraCalibrationPanel();
  @override
  ConsumerState<_CameraCalibrationPanel> createState() =>
      _CameraCalibrationPanelState();
}

class _CameraCalibrationPanelState
    extends ConsumerState<_CameraCalibrationPanel> {
  final _camera = TextEditingController(text: '0');
  int _rotation = 0;
  String _orientation = 'white_bottom';
  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Camera calibration',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                'Saves Pi webcam settings for the future OpenCV detector.'),
            TextField(
                controller: _camera,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Pi webcam index')),
            DropdownButton<int>(
                value: _rotation,
                isExpanded: true,
                items: const [0, 90, 180, 270]
                    .map((value) => DropdownMenuItem(
                        value: value, child: Text('Rotation $value°')))
                    .toList(),
                onChanged: (value) => setState(() => _rotation = value ?? 0)),
            DropdownButton<String>(
                value: _orientation,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: 'white_bottom', child: Text('White at bottom')),
                  DropdownMenuItem(
                      value: 'black_bottom', child: Text('Black at bottom'))
                ],
                onChanged: (value) =>
                    setState(() => _orientation = value ?? 'white_bottom')),
            FilledButton(
                onPressed: () => ref
                    .read(localBoardProvider.notifier)
                    .saveCameraCalibration(
                        cameraIndex: int.tryParse(_camera.text) ?? 0,
                        rotation: _rotation,
                        boardOrientation: _orientation),
                child: const Text('SAVE CALIBRATION')),
          ])));
}

class MoveProposal extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  const MoveProposal({super.key, required this.onSubmit});
  @override
  State<MoveProposal> createState() => _MoveProposalState();
}

class _MoveProposalState extends State<MoveProposal> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Move (e2e4)'))),
        const SizedBox(width: 8),
        FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty)
                widget.onSubmit(controller.text.trim());
            },
            child: const Text('PROPOSE')),
      ]);
}

class ChessPosition extends StatelessWidget {
  final String fen;
  const ChessPosition({super.key, required this.fen});
  @override
  Widget build(BuildContext context) {
    final ranks = fen.split(' ').first.split('/');
    final cells = <String>[];
    for (final rank in ranks) {
      for (final char in rank.split('')) {
        final count = int.tryParse(char);
        cells.addAll(count == null ? [char] : List.filled(count, ''));
      }
    }
    while (cells.length < 64) {
      cells.add('');
    }
    return AspectRatio(
        aspectRatio: 1,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 64,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8),
          itemBuilder: (_, index) => Container(
            color: ((index ~/ 8 + index) % 2 == 0)
                ? const Color(0xffead9b5)
                : const Color(0xffa87950),
            alignment: Alignment.center,
            child: Text(cells[index], style: const TextStyle(fontSize: 28)),
          ),
        ));
  }
}
