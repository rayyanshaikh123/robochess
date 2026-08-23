import 'package:flutter_test/flutter_test.dart';
import 'package:robochess_mobile/domain/models/device_credentials.dart';

Map<String, dynamic> onboardingData(DeviceCredentials credentials) => {
      'onboarding_token': credentials.onboardingToken,
      if (credentials.deviceSecret != null)
        'device_secret': credentials.deviceSecret,
    };

void main() {
  test('parses onboarding token and one-time device secret', () {
    final credentials = DeviceCredentials.fromJson({
      'onboarding_token': 'token-value',
      'device_secret': 'secret-value',
    });

    expect(credentials.onboardingToken, 'token-value');
    expect(credentials.deviceSecret, 'secret-value');
    expect(
      onboardingData(credentials),
      {'onboarding_token': 'token-value', 'device_secret': 'secret-value'},
    );
  });

  test('supports token-only onboarding responses', () {
    final credentials = DeviceCredentials.fromJson({
      'onboarding_token': 'token-value',
    });

    expect(credentials.onboardingToken, 'token-value');
    expect(credentials.deviceSecret, isNull);
    expect(onboardingData(credentials), {'onboarding_token': 'token-value'});
  });

  test('rejects responses without an onboarding token', () {
    expect(
      () => DeviceCredentials.fromJson(const {}),
      throwsA(isA<FormatException>()),
    );
  });
}
