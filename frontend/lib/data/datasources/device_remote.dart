import '../../core/network/api_client.dart';
import '../../domain/models/device_model.dart';

class DeviceRemoteDataSource {
  final ApiClient _client;

  DeviceRemoteDataSource(this._client);

  Future<DeviceModel> register({String? hardwareId}) async {
    final data = await _client.postJson('/device/register', auth: false, body: {
      'hardware_id': hardwareId,
    });
    return DeviceModel.fromJson(data);
  }

  Future<DeviceModel> connect(
      {required String deviceId, required String deviceSecret}) async {
    final data = await _client.postJson('/device/connect', auth: false, body: {
      'device_id': deviceId,
      'device_secret': deviceSecret,
    });
    return DeviceModel.fromJson(data);
  }

  Future<DeviceModel> link({required String pairingCode}) async {
    final data = await _client.postJson('/device/link', body: {
      'pairing_code': pairingCode,
    });
    return DeviceModel.fromJson(data);
  }

  Future<DeviceModel> status(String deviceId) async {
    final data = await _client.getJson('/device/status/$deviceId');
    return DeviceModel.fromJson(data);
  }

  Future<List<DeviceModel>> list() async {
    final data = await _client.getJson('/device/list');
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => DeviceModel.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<void> unlink(String deviceId) async {
    await _client.postJson('/device/unlink/$deviceId');
  }
}
