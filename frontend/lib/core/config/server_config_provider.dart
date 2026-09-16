import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'server_discovery.dart';
import 'server_config_store.dart';

/// Exposes the runtime-persisted server base URL, falling back to the
/// compile-time [AppConfig.apiBaseUrl].
class ServerConfigNotifier extends StateNotifier<String> {
  final ServerConfigStore _store;
  final String _compileTimeFallback;
  final ServerDiscovery _discovery;

  // The app historically saved hotspot / dev-machine addresses such as the
  // phone tether or a previous LAN machine. Those values are not valid once the
  // backend moves to the current Wi‑Fi network, so we migrate them back to the
  // current fallback server address instead of leaving the app stuck on an
  // unreachable IP.
  static const Set<String> _legacyHosts = {
    '172.20.10.2',
    '172.20.10.3',
    '172.20.10.4',
    '192.168.43.20',
    '192.168.43.25',
    '192.168.43.1',
  };

  ServerConfigNotifier(
      this._store, this._compileTimeFallback, [this._discovery = const ServerDiscovery()])
      : super(_compileTimeFallback) {
    _load();
  }

  Future<void> _load() async {
    final url = await _store.loadBaseUrl();
    if (url != null && url.isNotEmpty) {
      try {
        final normalized = _normalize(url);
        if (_isLegacyServerUrl(normalized)) {
          await _store.saveBaseUrl(_compileTimeFallback);
          state = _compileTimeFallback;
        } else {
          state = normalized;
        }
      } on ArgumentError {
        await _store.clear();
      }
    }
    await discoverIfUnavailable();
  }

  Future<bool> discoverIfUnavailable() async {
    final discovered = await _discovery.find(preferredUrl: state);
    if (discovered == null || discovered == state) {
      return discovered != null;
    }
    await _store.saveBaseUrl(discovered);
    state = discovered;
    return true;
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

  static bool _isLegacyServerUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return false;
    }

    final host = uri.host;
    if (host.isEmpty) {
      return false;
    }

    return _legacyHosts.contains(host) ||
        host.startsWith('172.20.10.') ||
        host.startsWith('192.168.43.');
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
