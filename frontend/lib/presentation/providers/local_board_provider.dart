import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/ble/robochess_ble.dart';
import '../../data/repositories/local_board_repository.dart';
import '../../data/repositories/local_state_store.dart';
import '../../domain/models/robochess_device.dart';
import '../../domain/models/robochess_protocol.dart';

final localBleServiceProvider = Provider<RoboChessBleClient>((ref) {
  final service = RoboChessBleClient();
  ref.onDispose(service.dispose);
  return service;
});

final localBoardRepositoryProvider = Provider<LocalBoardRepository>((ref) {
  return LocalBoardRepository(ref.read(localBleServiceProvider));
});

final localStateStoreProvider =
    Provider<LocalStateStore>((ref) => LocalStateStore());

class LocalBoardState {
  final List<RoboChessDevice> devices;
  final RoboChessDevice? selected;
  final PiState? piState;
  final PiNetworkStatus? network;
  final String? localApiBaseUrl;
  final LocalConnectionState connection;
  final bool scanning;
  final String? error;

  const LocalBoardState({
    this.devices = const [],
    this.selected,
    this.piState,
    this.network,
    this.localApiBaseUrl = AppConfig.piLocalApiBaseUrl,
    this.connection = LocalConnectionState.disconnected,
    this.scanning = false,
    this.error,
  });

  LocalBoardState copyWith({
    List<RoboChessDevice>? devices,
    RoboChessDevice? selected,
    PiState? piState,
    PiNetworkStatus? network,
    String? localApiBaseUrl,
    LocalConnectionState? connection,
    bool? scanning,
    String? error,
    bool clearError = false,
  }) =>
      LocalBoardState(
        devices: devices ?? this.devices,
        selected: selected ?? this.selected,
        piState: piState ?? this.piState,
        network: network ?? this.network,
        localApiBaseUrl: localApiBaseUrl ?? this.localApiBaseUrl,
        connection: connection ?? this.connection,
        scanning: scanning ?? this.scanning,
        error: clearError ? null : (error ?? this.error),
      );
}

class LocalBoardController extends StateNotifier<LocalBoardState> {
  final LocalBoardRepository repository;
  final LocalStateStore store;
  StreamSubscription<RoboChessBleDevice>? _devices;
  StreamSubscription<Map<String, dynamic>>? _notifications;

  LocalBoardController(this.repository, this.store)
      : super(const LocalBoardState()) {
    _notifications = repository.notifications.listen(_onMessage);
    _restoreState();
  }

  void _onDevice(RoboChessBleDevice item) {
    final device = RoboChessDevice(
        remoteId: item.result.device.remoteId.str,
        displayName: item.name,
        deviceId: null,
        rssi: item.rssi);
    final devices = [...state.devices];
    final index =
        devices.indexWhere((item) => item.remoteId == device.remoteId);
    if (index == -1) {
      devices.add(device);
    } else {
      devices[index] = device;
    }
    state = state.copyWith(devices: devices, scanning: false);
  }

  void _onMessage(Map<String, dynamic> value) {
    try {
      final message = repository.parse(value);
      final stateData = message.data['state'] ?? message.data['engine_state'];
      final networkData = message.data['network'];
      if (message.data['status'] == 'network_status' && networkData is Map) {
        final network =
            PiNetworkStatus.fromMap(Map<String, dynamic>.from(networkData));
        final reportedIp = network.ipAddress?.trim();
        final usableIp = reportedIp == null ||
                reportedIp.isEmpty ||
                reportedIp == '127.0.0.1' ||
                reportedIp == '0.0.0.0' ||
                reportedIp == 'localhost'
            ? null
            : reportedIp;
        state = state.copyWith(
          network: network,
          localApiBaseUrl: usableIp == null
              ? AppConfig.piLocalApiBaseUrl
              : 'http://$usableIp:8765',
          clearError: true,
        );
        return;
      }
      if ((message.type == 'control.result' || message.type == 'game.state') &&
          stateData is Map) {
        final next = PiState.fromMessage(message);
        if (repository.acceptState(next)) {
          state = state.copyWith(
              piState: next,
              connection: LocalConnectionState.ready,
              clearError: true);
          store.saveState(next);
        }
        if (next.state == 'recovery') {
          state = state.copyWith(connection: LocalConnectionState.recovering);
        }
      } else if (message.data['status'] == 'error' || message.type == 'error') {
        state = state.copyWith(
            error: message.data['error']?.toString() ?? message.type);
      }
    } catch (error) {
      state = state.copyWith(error: 'Invalid board message: $error');
    }
  }

  Future<void> _restoreState() async {
    final cached = await store.loadState();
    if (cached != null && mounted) state = state.copyWith(piState: cached);
  }

  Future<void> scan() async {
    state = state.copyWith(
        scanning: true,
        connection: LocalConnectionState.scanning,
        clearError: true);
    try {
      await _devices?.cancel();
      _devices = repository.scan().listen(_onDevice, onError: (Object error) {
        state = state.copyWith(
            error: 'Bluetooth scan failed: $error',
            scanning: false,
            connection: LocalConnectionState.disconnected);
      });
      // Scan results are streamed; retain the scanning state until a board appears.
    } catch (error) {
      state = state.copyWith(
          error: 'Bluetooth scan failed: $error',
          scanning: false,
          connection: LocalConnectionState.disconnected);
    }
  }

  Future<void> connect(RoboChessDevice device) async {
    state = state.copyWith(
        selected: device,
        connection: LocalConnectionState.connecting,
        clearError: true);
    try {
      final id = await repository.connectRemote(device.remoteId);
      await store.saveDevice(id);
      state = state.copyWith(
          selected: device.copyWith(
              deviceId: id, state: LocalConnectionState.connected),
          connection: LocalConnectionState.paired);
      await repository.requestState();
      await repository.requestNetworkStatus();
    } catch (error) {
      state = state.copyWith(
          error: 'Board connection failed: $error',
          connection: LocalConnectionState.disconnected);
    }
  }

  Future<void> confirmSetup() => repository.startSession();
  Future<void> proposeMove(String move) =>
      repository.proposeMove(move, state.piState?.version ?? 0);
  Future<void> reset() => repository.resetSession();
  Future<void> resume() => repository.resumeSession();
  Future<void> provisionWifi(String ssid, String password) async {
    try {
      await repository.provisionWifi(ssid, password);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: 'Wi-Fi provisioning failed: $error');
    }
  }

  Future<void> saveCameraCalibration(
      {required int cameraIndex,
      required int rotation,
      required String boardOrientation}) async {
    try {
      await repository.saveCameraCalibration(
          cameraIndex: cameraIndex,
          rotation: rotation,
          boardOrientation: boardOrientation);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: 'Camera calibration failed: $error');
    }
  }

  @override
  void dispose() {
    _devices?.cancel();
    _notifications?.cancel();
    repository.ble.disconnect();
    super.dispose();
  }
}

final localBoardProvider =
    StateNotifierProvider<LocalBoardController, LocalBoardState>((ref) {
  return LocalBoardController(ref.read(localBoardRepositoryProvider),
      ref.read(localStateStoreProvider));
});
