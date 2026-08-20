import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/ble_service.dart';
import '../../data/repositories/local_board_repository.dart';
import '../../data/repositories/local_state_store.dart';
import '../../domain/models/robochess_device.dart';
import '../../domain/models/robochess_protocol.dart';

final localBleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(service.dispose);
  return service;
});

final localBoardRepositoryProvider = Provider<LocalBoardRepository>((ref) {
  return LocalBoardRepository(ref.read(localBleServiceProvider));
});

final localStateStoreProvider = Provider<LocalStateStore>((ref) => LocalStateStore());

class LocalBoardState {
  final List<RoboChessDevice> devices;
  final RoboChessDevice? selected;
  final PiState? piState;
  final LocalConnectionState connection;
  final bool scanning;
  final String? error;

  const LocalBoardState({
    this.devices = const [],
    this.selected,
    this.piState,
    this.connection = LocalConnectionState.disconnected,
    this.scanning = false,
    this.error,
  });

  LocalBoardState copyWith({
    List<RoboChessDevice>? devices,
    RoboChessDevice? selected,
    PiState? piState,
    LocalConnectionState? connection,
    bool? scanning,
    String? error,
    bool clearError = false,
  }) => LocalBoardState(
        devices: devices ?? this.devices,
        selected: selected ?? this.selected,
        piState: piState ?? this.piState,
        connection: connection ?? this.connection,
        scanning: scanning ?? this.scanning,
        error: clearError ? null : (error ?? this.error),
      );
}

class LocalBoardController extends StateNotifier<LocalBoardState> {
  final LocalBoardRepository repository;
  final LocalStateStore store;
  StreamSubscription<RoboChessDevice>? _devices;
  StreamSubscription<List<int>>? _notifications;

  LocalBoardController(this.repository, this.store) : super(const LocalBoardState()) {
    _devices = repository.discoveredDevices.listen(_onDevice);
    _notifications = repository.notifications.listen(_onMessage);
    _restoreState();
  }

  void _onDevice(RoboChessDevice device) {
    final devices = [...state.devices];
    final index = devices.indexWhere((item) => item.remoteId == device.remoteId);
    if (index == -1) {
      devices.add(device);
    } else {
      devices[index] = device;
    }
    state = state.copyWith(devices: devices);
  }

  void _onMessage(List<int> bytes) {
    try {
      final message = repository.parse(bytes);
      if (message.type == 'state' || message.type == 'session.started' || message.type == 'move.accepted') {
        final next = PiState.fromMessage(message);
        if (repository.acceptState(next)) {
          state = state.copyWith(piState: next, connection: LocalConnectionState.ready, clearError: true);
          store.saveState(next);
        }
      } else if (message.type == 'recovery.required') {
        final next = PiState.fromMessage(message);
        state = state.copyWith(piState: next, connection: LocalConnectionState.recovering);
      } else if (message.type == 'move.rejected' || message.type == 'error') {
        state = state.copyWith(error: message.payload['reason']?.toString() ?? message.type);
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
    state = state.copyWith(scanning: true, connection: LocalConnectionState.scanning, clearError: true);
    try {
      await repository.ble.scan();
      state = state.copyWith(scanning: false, connection: LocalConnectionState.scanning);
    } catch (error) {
      state = state.copyWith(error: 'Bluetooth scan failed: $error', scanning: false, connection: LocalConnectionState.disconnected);
    }
  }

  Future<void> connect(RoboChessDevice device) async {
    state = state.copyWith(selected: device, connection: LocalConnectionState.connecting, clearError: true);
    try {
      await repository.ble.connect(device);
      await store.saveDevice(device.deviceId ?? device.remoteId);
      state = state.copyWith(selected: device.copyWith(state: LocalConnectionState.connected), connection: LocalConnectionState.paired);
      await repository.requestState();
    } catch (error) {
      state = state.copyWith(error: 'Board connection failed: $error', connection: LocalConnectionState.disconnected);
    }
  }

  Future<void> confirmSetup() => repository.startSession();
  Future<void> proposeMove(String move) => repository.proposeMove(move);
  Future<void> reset() => repository.resetSession();
  Future<void> resume() => repository.resumeSession();

  @override
  void dispose() {
    _devices?.cancel();
    _notifications?.cancel();
    repository.ble.disconnect();
    super.dispose();
  }
}

final localBoardProvider = StateNotifierProvider<LocalBoardController, LocalBoardState>((ref) {
  return LocalBoardController(ref.read(localBoardRepositoryProvider), ref.read(localStateStoreProvider));
});
