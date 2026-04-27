import '../../domain/models/auth_session.dart';
import '../datasources/auth_remote.dart';

class AuthRepository {
  final AuthRemoteDataSource _remote;

  AuthRepository(this._remote);

  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
    String? deviceId,
  }) {
    return _remote.register(
      email: email,
      password: password,
      displayName: displayName,
      deviceId: deviceId,
    );
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    String? deviceId,
  }) {
    return _remote.login(email: email, password: password, deviceId: deviceId);
  }

  Future<AuthSession> refresh(String refreshToken) =>
      _remote.refresh(refreshToken);

  Future<void> logout(String refreshToken) => _remote.logout(refreshToken);
}
