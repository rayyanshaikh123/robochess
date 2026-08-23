import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'server_config_store.dart';

/// Exposes the runtime-persisted server base URL, falling back to the
/// compile-time [AppConfig.apiBaseUrl].
class ServerConfigNotifier extends StateNotifier<String> {
  final ServerConfigStore _store;
  final String _compileTimeFallback;

  ServerConfigNotifier(this._store, this._compileTimeFallback)
      : super(_compileTimeFallback) {
    _load();
  }

  Future<void> _load() async {
    final url = await _store.loadBaseUrl();
    if (url != null && url.isNotEmpty) {
      state = url;
    }
  }

  /// Validates and persists a new base URL, then updates state so
  /// `apiClientProvider` / `gameSocketProvider` rebuild reactively.
  Future<void> update(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      throw ArgumentError('Enter a valid HTTP or HTTPS URL');
    }
    await _store.saveBaseUrl(trimmed);
    state = trimmed;
  }

  Future<void> reset() async {
    await _store.clear();
    state = _compileTimeFallback;
  }
}

final serverConfigStoreProvider = Provider<ServerConfigStore>(
  (ref) => ServerConfigStore(),
);

final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, String>((ref) {
  return ServerConfigNotifier(
    ref.read(serverConfigStoreProvider),
    AppConfig.apiBaseUrl,
  );
});
