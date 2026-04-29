import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/token_store.dart';
import '../../core/network/ws_client.dart';
import '../../data/datasources/auth_remote.dart';
import '../../data/datasources/device_remote.dart';
import '../../data/datasources/game_remote.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/game_repository.dart';
import '../../domain/models/auth_session.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokenStore: ref.read(tokenStoreProvider),
      timeout: Duration(seconds: AppConfig.apiTimeoutSeconds));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(AuthRemoteDataSource(ref.read(apiClientProvider)));
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(DeviceRemoteDataSource(ref.read(apiClientProvider)));
});

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(GameRemoteDataSource(ref.read(apiClientProvider)));
});

final gameSocketProvider = Provider<GameSocketClient>((ref) {
  return GameSocketClient(wsBaseUrl: AppConfig.wsBaseUrl);
});

class SessionController extends StateNotifier<AsyncValue<AuthSession?>> {
  final AuthRepository _authRepository;
  final TokenStore _tokenStore;

  SessionController(this._authRepository, this._tokenStore)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    final session = await _tokenStore.loadSession();
    state = AsyncValue.data(session);
  }

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final session = await _authRepository.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _tokenStore.saveSession(session);
      state = AsyncValue.data(session);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    try {
      final session =
          await _authRepository.login(email: email, password: password);
      await _tokenStore.saveSession(session);
      state = AsyncValue.data(session);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> logout() async {
    final session = state.value;
    if (session != null) {
      await _authRepository.logout(session.refreshToken);
    }
    await _tokenStore.clear();
    state = const AsyncValue.data(null);
  }
}

final sessionProvider =
    StateNotifierProvider<SessionController, AsyncValue<AuthSession?>>((ref) {
  return SessionController(
      ref.read(authRepositoryProvider), ref.read(tokenStoreProvider));
});
