class AuthSession {
  final String userId;
  final String accessToken;
  final String refreshToken;

  AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });
}
