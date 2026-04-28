class DeviceModel {
  final String deviceId;
  final String status;
  final String? pairingCode;
  final DateTime? pairingExpiresAt;
  final DateTime? lastSeen;

  DeviceModel({
    required this.deviceId,
    required this.status,
    this.pairingCode,
    this.pairingExpiresAt,
    this.lastSeen,
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
    );
  }
}
