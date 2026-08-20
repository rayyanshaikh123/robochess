import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      const Text('Nearby RoboChess Boards', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Local mode works over Bluetooth and does not require Internet or backend access.'),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: state.scanning ? null : () => ref.read(localBoardProvider.notifier).scan(),
        icon: const Icon(Icons.bluetooth_searching),
        label: Text(state.scanning ? 'SCANNING...' : 'FIND NEARBY BOARDS'),
      ),
      if (state.error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20),
      Expanded(child: ListView(children: state.devices.map((device) => _DeviceTile(device: device)).toList())),
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
          title: Text(device.displayName.isEmpty ? 'RoboChess board' : device.displayName),
          subtitle: Text('${device.deviceId ?? 'Device ID pending'}  •  RSSI ${device.rssi} dBm'),
          trailing: FilledButton(onPressed: () => ref.read(localBoardProvider.notifier).connect(device), child: const Text('CONNECT')),
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
        subtitle: Text('${state.connection.name}  •  ${state.selected?.deviceId ?? state.selected?.remoteId}'),
        trailing: Icon(Icons.circle, size: 12, color: state.connection == LocalConnectionState.ready ? Colors.green : Colors.orange),
      ),
      const Divider(),
      const Text('Board Command Dashboard', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Commands are sent directly to the Pi. Watch the Pi terminal for “BLE control received”.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: () => ref.read(localBoardProvider.notifier).confirmSetup(), icon: const Icon(Icons.smart_toy), label: const Text('START BOT GAME')),
        OutlinedButton(onPressed: () => ref.read(localBoardProvider.notifier).reset(), child: const Text('RESET')),
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
          const Text('Physical board recovery is required. Reset or resume only after confirming the board position.'),
        MoveProposal(onSubmit: (move) => ref.read(localBoardProvider.notifier).proposeMove(move)),
      ],
      const SizedBox(height: 16),
      MoveProposal(onSubmit: (move) => ref.read(localBoardProvider.notifier).proposeMove(move)),
      const SizedBox(height: 24),
      const _WifiPanel(),
      const SizedBox(height: 24),
      const _CameraCalibrationPanel(),
      if (state.error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]);
  }
}

class _WifiPanel extends ConsumerStatefulWidget {
  const _WifiPanel();
  @override ConsumerState<_WifiPanel> createState() => _WifiPanelState();
}
class _WifiPanelState extends ConsumerState<_WifiPanel> {
  final _ssid = TextEditingController(); final _password = TextEditingController();
  @override void dispose() { _ssid.dispose(); _password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Wi-Fi provisioning', style: TextStyle(fontWeight: FontWeight.bold)),
    TextField(controller: _ssid, decoration: const InputDecoration(labelText: 'Wi-Fi name (SSID)')),
    TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Wi-Fi password')),
    const SizedBox(height: 8),
    FilledButton(onPressed: () => ref.read(localBoardProvider.notifier).provisionWifi(_ssid.text.trim(), _password.text), child: const Text('SEND TO PI')),
  ])));
}

class _CameraCalibrationPanel extends ConsumerStatefulWidget { const _CameraCalibrationPanel(); @override ConsumerState<_CameraCalibrationPanel> createState() => _CameraCalibrationPanelState(); }
class _CameraCalibrationPanelState extends ConsumerState<_CameraCalibrationPanel> {
  final _camera = TextEditingController(text: '0'); int _rotation = 0; String _orientation = 'white_bottom';
  @override void dispose() { _camera.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Camera calibration', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Saves Pi webcam settings for the future OpenCV detector.'),
    TextField(controller: _camera, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pi webcam index')),
    DropdownButton<int>(value: _rotation, isExpanded: true, items: const [0, 90, 180, 270].map((value) => DropdownMenuItem(value: value, child: Text('Rotation $value°'))).toList(), onChanged: (value) => setState(() => _rotation = value ?? 0)),
    DropdownButton<String>(value: _orientation, isExpanded: true, items: const [DropdownMenuItem(value: 'white_bottom', child: Text('White at bottom')), DropdownMenuItem(value: 'black_bottom', child: Text('Black at bottom'))], onChanged: (value) => setState(() => _orientation = value ?? 'white_bottom')),
    FilledButton(onPressed: () => ref.read(localBoardProvider.notifier).saveCameraCalibration(cameraIndex: int.tryParse(_camera.text) ?? 0, rotation: _rotation, boardOrientation: _orientation), child: const Text('SAVE CALIBRATION')),
  ])));
}

class MoveProposal extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  const MoveProposal({super.key, required this.onSubmit});
  @override State<MoveProposal> createState() => _MoveProposalState();
}
class _MoveProposalState extends State<MoveProposal> {
  final controller = TextEditingController();
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Row(children: [
    Expanded(child: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Move (e2e4)'))),
    const SizedBox(width: 8),
    FilledButton(onPressed: () { if (controller.text.trim().isNotEmpty) widget.onSubmit(controller.text.trim()); }, child: const Text('PROPOSE')),
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
    while (cells.length < 64) cells.add('');
    return AspectRatio(aspectRatio: 1, child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(), itemCount: 64,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemBuilder: (_, index) => Container(
        color: ((index ~/ 8 + index) % 2 == 0) ? const Color(0xffead9b5) : const Color(0xffa87950),
        alignment: Alignment.center, child: Text(cells[index], style: const TextStyle(fontSize: 28)),
      ),
    ));
  }
}
