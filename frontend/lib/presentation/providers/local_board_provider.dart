import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/ble/robochess_ble.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/local_board_repository.dart';
import '../../data/repositories/local_state_store.dart';
import '../../data/repositories/pi_local_api.dart';
import 'session_provider.dart';
import '../../domain/models/pi_setup.dart';
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

/// A BLE board can be usable locally even when the Pi has no backend
/// credentials. The Link Board screen uses this to distinguish local linking
/// from account-backed cloud linking.
final localLinkedDeviceIdProvider = FutureProvider<String?>((ref) {
  return ref.read(localStateStoreProvider).loadDevice();
});

class LocalBoardState {
  final List<RoboChessDevice> devices;
  final RoboChessDevice? selected;
  final PiState? piState;
  final PiNetworkStatus? network;
  final List<PiWifiNetwork> wifiNetworks;
  final String? localApiBaseUrl;
  final PiSetupStatus? setup;
  final LocalConnectionState connection;
  final bool scanning;
  final bool setupLoading;
  final String? error;

  const LocalBoardState({
    this.devices = const [],
    this.selected,
    this.piState,
    this.network,
    this.wifiNetworks = const [],
    this.localApiBaseUrl = AppConfig.piLocalApiBaseUrl,
    this.setup,
    this.connection = LocalConnectionState.disconnected,
    this.scanning = false,
    this.setupLoading = false,
    this.error,
  });

  LocalBoardState copyWith({
    List<RoboChessDevice>? devices,
    RoboChessDevice? selected,
    PiState? piState,
    PiNetworkStatus? network,
    List<PiWifiNetwork>? wifiNetworks,
    String? localApiBaseUrl,
    PiSetupStatus? setup,
    LocalConnectionState? connection,
    bool? scanning,
    bool? setupLoading,
    String? error,
    bool clearError = false,
  }) =>
      LocalBoardState(
        devices: devices ?? this.devices,
        selected: selected ?? this.selected,
        piState: piState ?? this.piState,
        network: network ?? this.network,
        wifiNetworks: wifiNetworks ?? this.wifiNetworks,
        localApiBaseUrl: localApiBaseUrl ?? this.localApiBaseUrl,
        setup: setup ?? this.setup,
        connection: connection ?? this.connection,
        scanning: scanning ?? this.scanning,
        setupLoading: setupLoading ?? this.setupLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class LocalBoardController extends StateNotifier<LocalBoardState> {
  final LocalBoardRepository repository;
  final DeviceRepository deviceRepository;
  final LocalStateStore store;
  StreamSubscription<RoboChessBleDevice>? _devices;
  StreamSubscription<Map<String, dynamic>>? _notifications;

  LocalBoardController(this.repository, this.deviceRepository, this.store)
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
      if (message.data['status'] == 'network_scan') {
        final rawNetworks = message.data['networks'];
        final networks = rawNetworks is List
            ? rawNetworks
                .whereType<Map>()
                .map((item) =>
                    PiWifiNetwork.fromMap(Map<String, dynamic>.from(item)))
                .where((item) => item.ssid.isNotEmpty)
                .toList()
            : <PiWifiNetwork>[];
        state = state.copyWith(wifiNetworks: networks, clearError: true);
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
    final savedDeviceId = await store.loadDevice();
    if (savedDeviceId != null && savedDeviceId.isNotEmpty && mounted) {
      state = state.copyWith(
        selected: RoboChessDevice(
          remoteId: savedDeviceId,
          displayName: 'RoboChess Pi',
          deviceId: savedDeviceId,
          rssi: 0,
          state: LocalConnectionState.connected,
        ),
        connection: LocalConnectionState.paired,
      );
    }
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

  Future<String> connectBluetoothDevice(RoboChessBleDevice device) async {
    state = state.copyWith(
      connection: LocalConnectionState.connecting,
      clearError: true,
    );
    try {
      final id = await repository.connect(device);
      await store.saveDevice(id);
      state = state.copyWith(
        selected: RoboChessDevice(
          remoteId: device.result.device.remoteId.str,
          displayName: device.name,
          deviceId: id,
          rssi: device.rssi,
          state: LocalConnectionState.connected,
        ),
        connection: LocalConnectionState.paired,
      );
      try {
        final credentials =
            await deviceRepository.onboardingToken(deviceId: id);
        await repository.sendOnboardingCredentials(credentials);
      } catch (error) {
        state = state.copyWith(
          error: 'Board connected, but backend onboarding failed: $error',
        );
      }
      await repository.requestState();
      await repository.requestNetworkStatus();
      return id;
    } catch (error) {
      state = state.copyWith(
        error: 'Board connection failed: $error',
        connection: LocalConnectionState.disconnected,
      );
      rethrow;
    }
  }

  Future<void> refreshNetworkStatus() async {
    try {
      await repository.requestNetworkStatus();
    } catch (error) {
      state = state.copyWith(error: 'Pi network status failed: $error');
    }
  }

  Future<void> scanWifiNetworks() async {
    try {
      await repository.scanWifiNetworks();
    } catch (error) {
      state = state.copyWith(error: 'Pi Wi-Fi scan failed: $error');
    }
  }

  PiLocalApi _localApi() => PiLocalApi(
        baseUrl: state.localApiBaseUrl ?? AppConfig.piLocalApiBaseUrl,
      );

  Future<void> refreshSetup() async {
    final api = _localApi();
    try {
      state = state.copyWith(setupLoading: true, clearError: true);
      final setup = await api.setupStatus();
      state = state.copyWith(
        setup: setup,
        connection: setup.ready
            ? LocalConnectionState.ready
            : LocalConnectionState.connected,
        setupLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        setupLoading: false,
        error: 'Pi setup status failed: $error',
      );
    } finally {
      api.client.close();
    }
  }

  Future<void> loadPiModel() => _runSetupAction((api) => api.loadModel());
  Future<void> autoCalibrate() => _runSetupAction((api) => api.autoCalibrate());
  Future<void> manualCalibrate(List<List<double>> corners) =>
      _runSetupAction((api) => api.manualCalibrate(corners));
  Future<void> validateStartingPosition() =>
      _runSetupAction((api) => api.validateStart());
  Future<void> homePiGantry() => _runSetupAction((api) => api.homeGantry());

  Future<void> _runSetupAction(
      Future<Map<String, dynamic>> Function(PiLocalApi api) action) async {
    final api = _localApi();
    try {
      state = state.copyWith(setupLoading: true, clearError: true);
      await action(api);
      await refreshSetup();
    } catch (error) {
      state = state.copyWith(
        setupLoading: false,
        error: 'Pi setup action failed: $error',
      );
    } finally {
      api.client.close();
    }
  }

  Future<void> confirmSetup() async {
    final api = _localApi();
    try {
      state = state.copyWith(setupLoading: true, clearError: true);
      final result = await api.startGame();
      final raw = result['state'];
      if (raw is Map) {
        final message = RoboChessMessage(
          type: 'control.result',
          requestId: '',
          deviceId: state.selected?.deviceId ?? '',
          data: {'state': Map<String, dynamic>.from(raw)},
        );
        final next = PiState.fromMessage(message);
        state = state.copyWith(piState: next);
      }
      state = state.copyWith(
        connection: LocalConnectionState.ready,
        setupLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        setupLoading: false,
        error: 'Pi game start failed: $error',
      );
    } finally {
      api.client.close();
    }
  }

  Future<void> _runGameAction(
      Future<Map<String, dynamic>> Function(PiLocalApi api) action) async {
    final api = _localApi();
    try {
      final result = await action(api);
      final raw = result['state'];
      if (raw is Map) {
        final message = RoboChessMessage(
          type: 'control.result',
          requestId: '',
          deviceId: state.selected?.deviceId ?? '',
          data: {'state': Map<String, dynamic>.from(raw)},
        );
        final next = PiState.fromMessage(message);
        state = state.copyWith(piState: next);
        await store.saveState(next);
      }
    } catch (error) {
      state = state.copyWith(error: 'Pi game action failed: $error');
    } finally {
      api.client.close();
    }
  }

  Future<void> proposeMove(String move) => _runGameAction(
        (api) => api.gameMove(move, state.piState?.version),
      );
  Future<void> reset() => _runGameAction((api) => api.resetGame());
  Future<void> undo() => _runGameAction((api) => api.undoGame());
  Future<void> resume() => _runGameAction((api) => api.resumeGame());
  void applyNetworkStatus(Map<String, dynamic> data) {
    final network = PiNetworkStatus.fromMap(data);
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
      localApiBaseUrl:
          usableIp == null ? state.localApiBaseUrl : 'http://$usableIp:8765',
      clearError: true,
    );
  }

  Future<void> adoptBoard(
      {required String remoteId, required String deviceId}) async {
    await store.saveDevice(deviceId);
    state = state.copyWith(
      selected: RoboChessDevice(
        remoteId: remoteId,
        displayName: 'RoboChess board',
        deviceId: deviceId,
        rssi: 0,
        state: LocalConnectionState.connected,
      ),
      connection: LocalConnectionState.paired,
      clearError: true,
    );
  }

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
  return LocalBoardController(
    ref.read(localBoardRepositoryProvider),
    ref.read(deviceRepositoryProvider),
    ref.read(localStateStoreProvider),
  );
});
