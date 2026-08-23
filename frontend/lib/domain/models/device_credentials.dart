class DeviceCredentials {
  final String onboardingToken;
  final String? deviceSecret;

  const DeviceCredentials({
    required this.onboardingToken,
    this.deviceSecret,
  });

  factory DeviceCredentials.fromJson(Map<String, dynamic> json) {
    final token = json['onboarding_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const FormatException('Backend did not return an onboarding token');
    }
    final secret = json['device_secret']?.toString();
    return DeviceCredentials(
      onboardingToken: token,
      deviceSecret: secret == null || secret.isEmpty ? null : secret,
    );
  }
}
