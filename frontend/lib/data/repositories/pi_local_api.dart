import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PiLocalApi {
  final String baseUrl;
  final http.Client client;

  PiLocalApi({required this.baseUrl, http.Client? client})
      : client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static const _requestTimeout = Duration(seconds: 5);

  Future<Map<String, dynamic>> networkStatus() async {
    final response = await client
        .get(_uri('/local/network/status'))
        .timeout(_requestTimeout);
    if (response.statusCode >= 400) throw Exception('Pi network status failed');
    return Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map)['data'] as Map);
  }

  Future<Uint8List> cameraFrame({bool preview = false}) async {
    final endpoint = preview ? '/local/camera/preview' : '/local/camera/frame';
    final response = await client.get(_uri(endpoint)).timeout(_requestTimeout);
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
    final response = await client.send(request);
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
}
