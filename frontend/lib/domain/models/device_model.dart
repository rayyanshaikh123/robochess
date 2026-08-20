class DeviceModel {
  final String deviceId;
  final String status;
  final String? pairingCode;
  final DateTime? pairingExpiresAt;
  final DateTime? lastSeen;
  final String wifiStatus;
  final String backendStatus;
  final String? firmwareVersion;
  final String? protocolVersion;
  final String? lastError;

  DeviceModel({
    required this.deviceId,
    required this.status,
    this.pairingCode,
    this.pairingExpiresAt,
    this.lastSeen,
    this.wifiStatus = 'unknown',
    this.backendStatus = 'unknown',
    this.firmwareVersion,
    this.protocolVersion,
    this.lastError,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      deviceId: json['device_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      pairingCode: json['pairing_code']?.toString(),
      pairingExpiresAt: json['pairing_expires_at'] != null
          ? DateTime.tryParse(json['pairing_expires_at'].toString())
          : null,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,
      wifiStatus: json['wifi_status']?.toString() ?? 'unknown',
      backendStatus: json['backend_status']?.toString() ?? 'unknown',
      firmwareVersion: json['firmware_version']?.toString(),
      protocolVersion: json['protocol_version']?.toString(),
      lastError: json['last_error']?.toString(),
    );
  }
}
