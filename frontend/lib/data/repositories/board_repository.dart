import '../../domain/models/calibration_frame.dart';
import '../datasources/board_remote.dart';

class BoardRepository {
  final BoardRemoteDataSource _remote;

  BoardRepository(this._remote);

  Future<void> loadModel({String? modelPath}) =>
      _remote.loadModel(modelPath: modelPath);

  Future<void> autoCalibrate() => _remote.autoCalibrate();

  Future<void> manualCalibrate(List<List<double>> corners) =>
      _remote.manualCalibrate(corners);

  Future<Map<String, dynamic>> validateStart() => _remote.validateStart();

  Future<Map<String, dynamic>> debugCalibration() => _remote.debugCalibration();

  Future<void> forceValidate() => _remote.forceValidate();

  Future<CalibrationFrame> captureFrame() => _remote.captureFrame();

  Future<CalibrationFrame> capturePreview() => _remote.capturePreview();

  Future<Map<String, dynamic>> detectMoveSnapshot() =>
      _remote.detectMoveSnapshot();

  Future<Map<String, dynamic>> detectMoveSnapshotIfClear() =>
      _remote.detectMoveSnapshotIfClear();
}
