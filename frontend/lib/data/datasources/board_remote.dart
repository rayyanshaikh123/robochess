import '../../core/network/api_client.dart';
import '../../domain/models/calibration_frame.dart';

class BoardRemoteDataSource {
  final ApiClient _client;

  BoardRemoteDataSource(this._client);

  Future<void> loadModel({String? modelPath}) async {
    await _client.postJson('/model/load', body: {
      if (modelPath != null && modelPath.isNotEmpty) 'model_path': modelPath,
    });
  }

  Future<void> autoCalibrate() async {
    await _client.postJson('/calibrate/auto');
  }

  Future<void> manualCalibrate(List<List<double>> corners) async {
    await _client.postJson('/calibrate/manual', body: {'corners': corners});
  }

  Future<Map<String, dynamic>> validateStart() async {
    return _client.postJson('/calibrate/validate');
  }

  Future<Map<String, dynamic>> debugCalibration() async {
    return _client.getJson('/calibrate/debug');
  }

  Future<void> forceValidate() async {
    await _client.postJson('/calibrate/force');
  }

  Future<CalibrationFrame> captureFrame() async {
    final data = await _client.getJson('/calibrate/frame');
    return CalibrationFrame.fromJson(data);
  }

  Future<CalibrationFrame> capturePreview() async {
    final data = await _client.getJson('/calibrate/preview');
    return CalibrationFrame.fromJson(data);
  }

  Future<Map<String, dynamic>> detectMoveSnapshot() async {
    return _client.postJson('/move/detect');
  }

  Future<Map<String, dynamic>> detectMoveSnapshotIfClear() async {
    return _client.postJson('/move/detect_if_clear');
  }
}
