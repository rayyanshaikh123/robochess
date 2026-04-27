import '../../core/network/api_client.dart';
import '../../domain/models/auth_session.dart';

class AuthRemoteDataSource {
  final ApiClient _client;

  AuthRemoteDataSource(this._client);

  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
    String? deviceId,
  }) async {
    final data = await _client.postJson('/auth/register', auth: false, body: {
      'email': email,
      'password': password,
      'display_name': displayName,
      'device_id': deviceId,
    });
    return AuthSession(
      userId: data['user_id']?.toString() ?? '',
      accessToken: data['access_token']?.toString() ?? '',
      refreshToken: data['refresh_token']?.toString() ?? '',
    );
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    String? deviceId,
  }) async {
    final data = await _client.postJson('/auth/login', auth: false, body: {
      'email': email,
      'password': password,
      'device_id': deviceId,
    });
    return AuthSession(
      userId: data['user_id']?.toString() ?? '',
      accessToken: data['access_token']?.toString() ?? '',
      refreshToken: data['refresh_token']?.toString() ?? '',
    );
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final data = await _client.postJson('/auth/refresh', auth: false, body: {
      'refresh_token': refreshToken,
    });
    return AuthSession(
      userId: data['user_id']?.toString() ?? '',
      accessToken: data['access_token']?.toString() ?? '',
      refreshToken: data['refresh_token']?.toString() ?? '',
    );
  }

  Future<void> logout(String refreshToken) async {
    await _client.postJson('/auth/logout', auth: false, body: {
      'refresh_token': refreshToken,
    });
  }
}
