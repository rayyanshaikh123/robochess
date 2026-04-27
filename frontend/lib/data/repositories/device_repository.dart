import '../../domain/models/device_model.dart';
import '../datasources/device_remote.dart';

class DeviceRepository {
  final DeviceRemoteDataSource _remote;

  DeviceRepository(this._remote);

  Future<DeviceModel> register({String? hardwareId}) =>
      _remote.register(hardwareId: hardwareId);

  Future<DeviceModel> connect(
      {required String deviceId, required String deviceSecret}) {
    return _remote.connect(deviceId: deviceId, deviceSecret: deviceSecret);
  }

  Future<DeviceModel> link({required String pairingCode}) =>
      _remote.link(pairingCode: pairingCode);

  Future<DeviceModel> status(String deviceId) => _remote.status(deviceId);

  Future<List<DeviceModel>> list() => _remote.list();

  Future<void> unlink(String deviceId) => _remote.unlink(deviceId);
}
