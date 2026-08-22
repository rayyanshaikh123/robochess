import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors/api_exception.dart';
import 'token_store.dart';

class ApiClient {
  final String baseUrl;
  final TokenStore tokenStore;
  final http.Client _client;
  final Duration timeout;

  ApiClient(
      {required this.baseUrl,
      required this.tokenStore,
      http.Client? client,
      Duration? timeout})
      : _client = client ?? http.Client(),
        timeout = timeout ?? const Duration(seconds: 20);

  Future<Map<String, dynamic>> getJson(String path,
      {Map<String, String>? queryParameters, bool auth = true}) async {
    final uri =
        Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
    final headers = await _headers(auth: auth);
    final response = await _send(_client.get(uri, headers: headers));
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> postJson(String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(auth: auth);
    final response = await _send(
      _client.post(uri, headers: headers, body: jsonEncode(body ?? {})),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> patchJson(String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(auth: auth);
    final response = await _send(
      _client.patch(uri, headers: headers, body: jsonEncode(body ?? {})),
    );
    return _handleResponse(response);
  }

  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and retry.');
    } on SocketException {
      throw ApiException('Network error. Check your connection and retry.');
    }
  }

  Future<Map<String, String>> _headers({required bool auth}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final session = await tokenStore.loadSession();
      if (session != null) {
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }
    return headers;
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw ApiException('Request failed');
      }
      return {};
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(payload['message']?.toString() ?? 'Request failed',
          details: payload['data'] as Map<String, dynamic>?);
    }
    if (payload['status'] == 'error') {
      throw ApiException(payload['message']?.toString() ?? 'Request failed',
          details: payload['data'] as Map<String, dynamic>?);
    }
    return (payload['data'] as Map<String, dynamic>?) ?? {};
  }
}
