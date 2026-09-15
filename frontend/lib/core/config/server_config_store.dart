import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists a runtime-configurable backend base URL in FlutterSecureStorage.
///
/// Uses the distinct key `'server_base_url'` so it never collides with any
/// [TokenStore] key (`access_token`, `refresh_token`, `user_id`,
/// `selected_device_id`).
class ServerConfigStore {
  static const baseUrlKey = 'server_base_url_v2';
  static const legacyBaseUrlKey = 'server_base_url';

  final FlutterSecureStorage _storage;

  ServerConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> loadBaseUrl() async {
    return await _storage.read(key: baseUrlKey) ??
        await _storage.read(key: legacyBaseUrlKey);
  }

  Future<void> saveBaseUrl(String url) =>
      _storage.write(key: baseUrlKey, value: url);

  Future<void> clear() async {
    await _storage.delete(key: baseUrlKey);
    await _storage.delete(key: legacyBaseUrlKey);
  }
}
