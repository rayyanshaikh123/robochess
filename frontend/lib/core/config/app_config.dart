class AppConfig {
  static const piLocalApiBaseUrl = String.fromEnvironment(
    'PI_LOCAL_API_BASE_URL',
    defaultValue: 'http://172.20.10.2:8765',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Current Mac address on the RoboChess/iPhone local network. Override
    // with --dart-define=API_BASE_URL=... when the network changes.
    defaultValue: 'http://192.168.0.107:8000',
  );

  static const wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://192.168.0.107:8000/ws',
  );

  static const apiTimeoutSeconds = int.fromEnvironment(
    'API_TIMEOUT_SECONDS',
    defaultValue: 20,
  );

  static const boardModelRef = String.fromEnvironment(
    'BOARD_MODEL_REF',
    defaultValue: '',
  );

  static const roboChessServiceUuid = String.fromEnvironment(
    'ROBOCHESS_SERVICE_UUID',
    defaultValue: '0000f00d-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessDeviceInfoUuid = String.fromEnvironment(
    'ROBOCHESS_DEVICE_INFO_UUID',
    defaultValue: '0000f00e-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessControlUuid = String.fromEnvironment(
    'ROBOCHESS_CONTROL_UUID',
    defaultValue: '0000f00f-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessWifiUuid = String.fromEnvironment(
    'ROBOCHESS_WIFI_UUID',
    defaultValue: '0000f010-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessStatusUuid = String.fromEnvironment(
    'ROBOCHESS_STATUS_UUID',
    defaultValue: '0000f011-0000-1000-8000-00805f9b34fb',
  );
}
