import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PiLocalApi {
  final String baseUrl;
  final http.Client client;

  PiLocalApi({required this.baseUrl, http.Client? client}) : client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> networkStatus() async {
    final response = await client.get(_uri('/local/network/status'));
    if (response.statusCode >= 400) throw Exception('Pi network status failed');
    return Map<String, dynamic>.from((jsonDecode(response.body) as Map)['data'] as Map);
  }

  Future<Uint8List> cameraFrame({bool preview = false}) async {
    final response = await client.get(_uri(preview ? '/local/camera/preview' : '/local/camera/frame'));
    if (response.statusCode >= 400) throw Exception('Pi camera frame failed');
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> saveCalibration({required List<List<double>> corners, String orientation = 'white_bottom'}) async {
    final response = await client.post(
      _uri('/local/calibration/manual'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'corners': corners, 'board_orientation': orientation}),
    );
    if (response.statusCode >= 400) throw Exception('Pi calibration failed');
    return Map<String, dynamic>.from((jsonDecode(response.body) as Map)['data'] as Map);
  }
}
