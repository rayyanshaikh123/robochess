import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/auth_session.dart';

class TokenStore {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _deviceIdKey = 'selected_device_id';

  final FlutterSecureStorage _storage;

  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveSession(AuthSession session) async {
    await _storage.write(key: _accessKey, value: session.accessToken);
    await _storage.write(key: _refreshKey, value: session.refreshToken);
    await _storage.write(key: _userIdKey, value: session.userId);
  }

  Future<AuthSession?> loadSession() async {
    final accessToken = await _storage.read(key: _accessKey);
    final refreshToken = await _storage.read(key: _refreshKey);
    final userId = await _storage.read(key: _userIdKey);
    if (accessToken == null || refreshToken == null || userId == null) {
      return null;
    }
    return AuthSession(
        userId: userId, accessToken: accessToken, refreshToken: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _deviceIdKey);
  }

  Future<void> saveSelectedDevice(String deviceId) async {
    await _storage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<String?> loadSelectedDevice() async {
    return _storage.read(key: _deviceIdKey);
  }

  Future<void> clearSelectedDevice() async {
    await _storage.delete(key: _deviceIdKey);
  }
}
