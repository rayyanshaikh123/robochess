import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/device_repository.dart';
import '../../domain/models/device_model.dart';
import '../../core/config/app_config.dart';
import '../../core/network/token_store.dart';
import '../../core/network/ws_client.dart';
import 'session_provider.dart';

final deviceSocketProvider = Provider<DeviceSocketClient>((ref) {
  return DeviceSocketClient(
    wsBaseUrl: AppConfig.wsBaseUrl,
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final deviceListProvider =
    StateNotifierProvider<DeviceListController, AsyncValue<List<DeviceModel>>>(
        (ref) {
  return DeviceListController(
    ref.watch(deviceRepositoryProvider),
    ref.watch(deviceSocketProvider),
  );
});

class DeviceListController
    extends StateNotifier<AsyncValue<List<DeviceModel>>> {
  final DeviceRepository _repository;
  final DeviceSocketClient _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  DeviceListController(this._repository, this._socket)
      : super(const AsyncValue.loading()) {
    _init().catchError((_, __) {});
  }

  Future<void> _init() async {
    try {
      await _socket.connect();
      _sub = _socket.stream.listen(_handleEvent, onError: (e) {
        // Socket stream error handled gracefully
      });
    } catch (_) {
      // Offline / unreachable socket handled gracefully
    }
    await load();
  }

  Future<void> load() async {
    try {
      final items = await _repository.list();
      state = AsyncValue.data(items);
      final deviceIds = items.map((device) => device.deviceId).toList();
      if (deviceIds.isNotEmpty) {
        _socket.subscribe(deviceIds);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> unlink(String deviceId) async {
    await _repository.unlink(deviceId);
    await load();
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['type'] != 'device.status') return;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final deviceId = data['device_id']?.toString();
    if (deviceId == null) return;
    state = state.whenData((items) {
      return items.map((device) {
        if (device.deviceId != deviceId) return device;
        return DeviceModel.fromJson({...data, 'device_id': deviceId});
      }).toList();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class SelectedDeviceController extends StateNotifier<String?> {
  final TokenStore _tokenStore;

  SelectedDeviceController(this._tokenStore) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final session = await _tokenStore.loadSession();
    state =
        session?.userId == null ? null : await _tokenStore.loadSelectedDevice();
  }

  Future<void> select(String deviceId) async {
    state = deviceId;
    await _tokenStore.saveSelectedDevice(deviceId);
  }

  Future<void> clear() async {
    state = null;
    await _tokenStore.clearSelectedDevice();
  }
}

final selectedDeviceProvider =
    StateNotifierProvider<SelectedDeviceController, String?>((ref) {
  return SelectedDeviceController(ref.watch(tokenStoreProvider));
});
