import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../domain/models/pi_setup.dart';

class PiLocalApi {
  final String baseUrl;
  final http.Client client;

  PiLocalApi({required this.baseUrl, http.Client? client})
      : client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static const _requestTimeout = Duration(seconds: 5);
  static const _cameraRequestTimeout = Duration(seconds: 2);

  Future<PiSetupStatus> setupStatus() async {
    final response =
        await client.get(_uri('/local/setup/status')).timeout(_requestTimeout);
    final data = await _data(response, 'Pi setup status failed');
    return PiSetupStatus.fromJson(data);
  }

  Future<Map<String, dynamic>> localStatus() async {
    final response =
        await client.get(_uri('/local/status')).timeout(_requestTimeout);
    return _data(response, 'Pi local status failed');
  }

  Future<Map<String, dynamic>> networkStatus() async {
    final response = await client
        .get(_uri('/local/network/status'))
        .timeout(_requestTimeout);
    if (response.statusCode >= 400) throw Exception('Pi network status failed');
    return Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map)['data'] as Map);
  }

  Future<Map<String, dynamic>> modelStatus() async {
    final response =
        await client.get(_uri('/local/model/status')).timeout(_requestTimeout);
    return _data(response, 'Pi model status failed');
  }

  Future<Map<String, dynamic>> loadModel() async {
    final response =
        await client.post(_uri('/local/model/load')).timeout(_requestTimeout);
    return _data(response, 'Pi model load failed');
  }

  Future<Map<String, dynamic>> validateStart() async {
    final response = await client
        .post(_uri('/local/calibration/validate-start'))
        .timeout(_requestTimeout);
    return _data(response, 'Pi board validation failed');
  }

  Future<Map<String, dynamic>> debugCalibration() async {
    final response = await client
        .get(_uri('/local/calibration/debug'))
        .timeout(_requestTimeout);
    return _data(response, 'Pi calibration diagnostics failed');
  }

  Future<Map<String, dynamic>> forceValidate() async {
    final response = await client
        .post(_uri('/local/calibration/force'))
        .timeout(_requestTimeout);
    return _data(response, 'Pi force validation failed');
  }

  Future<Map<String, dynamic>> homeGantry() async {
    final response = await client
        .post(_uri('/local/gantry/home'))
        .timeout(const Duration(seconds: 100));
    return _data(response, 'Pi gantry homing failed');
  }

  Future<Map<String, dynamic>> gantryStatus() async {
    final response =
        await client.get(_uri('/local/gantry/status')).timeout(_requestTimeout);
    return _data(response, 'Pi gantry status failed');
  }

  Future<Map<String, dynamic>> startGame() async {
    final response =
        await client.post(_uri('/local/game/start')).timeout(_requestTimeout);
    return _data(response, 'Pi game start failed');
  }

  Future<Map<String, dynamic>> gameState() async {
    final response =
        await client.get(_uri('/local/game/state')).timeout(_requestTimeout);
    return _data(response, 'Pi game state failed');
  }

  Future<Map<String, dynamic>> gameMove(
      String uci, int? expectedVersion) async {
    final response = await client
        .post(
          _uri('/local/game/move'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'uci': uci,
            if (expectedVersion != null) 'expected_version': expectedVersion,
          }),
        )
        .timeout(_requestTimeout);
    return _data(response, 'Pi move failed');
  }

  Future<Map<String, dynamic>> resetGame() async {
    final response =
        await client.post(_uri('/local/game/reset')).timeout(_requestTimeout);
    return _data(response, 'Pi game reset failed');
  }

  Future<Map<String, dynamic>> undoGame() async {
    final response =
        await client.post(_uri('/local/game/undo')).timeout(_requestTimeout);
    return _data(response, 'Pi game undo failed');
  }

  Future<Map<String, dynamic>> resumeGame() async {
    final response =
        await client.post(_uri('/local/game/start')).timeout(_requestTimeout);
    return _data(response, 'Pi game resume failed');
  }

  Future<Map<String, dynamic>> detectMove() async {
    final response =
        await client.post(_uri('/local/move/detect')).timeout(_requestTimeout);
    return _data(response, 'Pi move detection failed');
  }

  Future<Map<String, dynamic>> analyzeAndReply() async {
    final response = await client
        .post(_uri('/local/move/analyze-and-reply'))
        .timeout(_requestTimeout);
    return _data(response, 'Pi move analysis failed');
  }

  Future<Map<String, dynamic>> autoDetectReady() async {
    final response = await client
        .get(_uri('/local/move/auto-detect-ready'))
        .timeout(_requestTimeout);
    return _data(response, 'Pi auto-detection failed');
  }

  Future<Map<String, dynamic>> _data(
      http.Response response, String fallback) async {
    Map<String, dynamic> payload = const {};
    try {
      payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {}
    if (response.statusCode >= 400 || payload['status'] == 'error') {
      final rawDetail = payload['detail'];
      final detail = rawDetail is Map
          ? rawDetail['message']?.toString() ?? fallback
          : rawDetail?.toString() ?? payload['message']?.toString() ?? fallback;
      throw Exception(detail);
    }
    return Map<String, dynamic>.from((payload['data'] as Map?) ?? const {});
  }

  Future<Uint8List> cameraFrame({
    bool preview = false,
    Duration timeout = _cameraRequestTimeout,
  }) async {
    final endpoint = preview ? '/local/camera/preview' : '/local/camera/frame';
    final response = await client.get(_uri(endpoint)).timeout(timeout);
    if (response.statusCode >= 400) {
      throw Exception('Pi camera returned HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) {
      throw Exception('Pi camera returned an empty frame');
    }
    return response.bodyBytes;
  }

  /// Decodes the Pi's multipart MJPEG response into individual JPEG frames.
  Stream<Uint8List> cameraStream() async* {
    final request = http.Request('GET', _uri('/local/camera/stream'));
    final response = await client.send(request).timeout(_requestTimeout);
    if (response.statusCode >= 400) {
      throw Exception('Pi camera stream returned HTTP ${response.statusCode}');
    }

    var buffer = <int>[];
    await for (final chunk in response.stream) {
      buffer.addAll(chunk);
      while (true) {
        final start = _findMarker(buffer, const [0xff, 0xd8]);
        if (start < 0) {
          if (buffer.length > 2) {
            buffer = buffer.sublist(buffer.length - 2);
          }
          break;
        }
        final end = _findMarker(buffer, const [0xff, 0xd9], start + 2);
        if (end < 0) {
          if (start > 0) {
            buffer = buffer.sublist(start);
          }
          break;
        }
        final frame = Uint8List.fromList(buffer.sublist(start, end + 2));
        buffer = buffer.sublist(end + 2);
        yield frame;
      }
    }
  }

  int _findMarker(List<int> bytes, List<int> marker, [int from = 0]) {
    for (var i = from; i <= bytes.length - marker.length; i++) {
      var match = true;
      for (var j = 0; j < marker.length; j++) {
        if (bytes[i + j] != marker[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  Future<Map<String, dynamic>> saveCalibration(
      {required List<List<double>> corners,
      String orientation = 'white_bottom'}) async {
    final response = await client.post(
      _uri('/local/calibration/manual'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'corners': corners, 'board_orientation': orientation}),
    );
    if (response.statusCode >= 400) throw Exception('Pi calibration failed');
    return Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map)['data'] as Map);
  }

  Future<Map<String, dynamic>> manualCalibrate(List<List<double>> corners,
      {String orientation = 'white_bottom'}) async {
    final response = await client
        .post(
          _uri('/local/calibration/manual'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'corners': corners,
            'board_orientation': orientation,
          }),
        )
        .timeout(_requestTimeout);
    return _data(response, 'Pi manual calibration failed');
  }

  Future<Map<String, dynamic>> autoCalibrate() async {
    final response = await client
        .post(_uri('/local/calibration/auto'))
        .timeout(_requestTimeout);
    if (response.statusCode >= 400) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(
          body?['detail']?.toString() ?? 'Automatic calibration failed');
    }
    return Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map)['data'] as Map);
  }
}
