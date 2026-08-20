enum LocalConnectionState { disconnected, scanning, connecting, connected, paired, ready, recovering }

class RoboChessDevice {
  final String remoteId;
  final String displayName;
  final String? deviceId;
  final int rssi;
  final LocalConnectionState state;

  const RoboChessDevice({
    required this.remoteId,
    required this.displayName,
    this.deviceId,
    required this.rssi,
    this.state = LocalConnectionState.disconnected,
  });

  RoboChessDevice copyWith({String? deviceId, int? rssi, LocalConnectionState? state}) => RoboChessDevice(
        remoteId: remoteId,
        displayName: displayName,
        deviceId: deviceId ?? this.deviceId,
        rssi: rssi ?? this.rssi,
        state: state ?? this.state,
      );
}
