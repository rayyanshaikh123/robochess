class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8000/ws',
  );

  static const apiTimeoutSeconds = int.fromEnvironment(
    'API_TIMEOUT_SECONDS',
    defaultValue: 20,
  );

  static const boardModelRef = String.fromEnvironment(
    'BOARD_MODEL_REF',
    defaultValue: 'rf://chess-bprbi-ffewq/1',
  );

  static const roboChessServiceUuid = String.fromEnvironment(
    'ROBOCHESS_SERVICE_UUID',
    defaultValue: '0000f00d-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessRxUuid = String.fromEnvironment(
    'ROBOCHESS_RX_UUID',
    defaultValue: '0000f00e-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessTxUuid = String.fromEnvironment(
    'ROBOCHESS_TX_UUID',
    defaultValue: '0000f00f-0000-1000-8000-00805f9b34fb',
  );

  static const roboChessStatusUuid = String.fromEnvironment(
    'ROBOCHESS_STATUS_UUID',
    defaultValue: '0000f010-0000-1000-8000-00805f9b34fb',
  );
}
