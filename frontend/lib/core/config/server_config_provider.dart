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
      try {
        state = _normalize(url);
      } on ArgumentError {
        await _store.clear();
      }
    }
  }

  static String _normalize(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        (uri.path != '' && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError('Enter a valid HTTP or HTTPS server URL');
    }
    return uri.replace(path: '').toString().replaceFirst(RegExp(r'/$'), '');
  }

  /// Validates and persists a new base URL, then updates state so
  /// `apiClientProvider` / `gameSocketProvider` rebuild reactively.
  Future<void> update(String url) async {
    final normalized = _normalize(url);
    await _store.saveBaseUrl(normalized);
    state = normalized;
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
