import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/models/auth_session.dart';
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
    return _handleResponse(response, uri: uri, method: 'GET', auth: auth, headers: headers);
  }

  Future<Map<String, dynamic>> postJson(String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(auth: auth);
    final response = await _send(
      _client.post(uri, headers: headers, body: jsonEncode(body ?? {})),
    );
    return _handleResponse(response, uri: uri, method: 'POST', auth: auth, headers: headers, body: body ?? const {});
  }

  Future<Map<String, dynamic>> patchJson(String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(auth: auth);
    final response = await _send(
      _client.patch(uri, headers: headers, body: jsonEncode(body ?? {})),
    );
    return _handleResponse(response, uri: uri, method: 'PATCH', auth: auth, headers: headers, body: body ?? const {});
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

  Future<Map<String, dynamic>> _handleResponse(
    http.Response response, {
    required Uri uri,
    required String method,
    required bool auth,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    if (response.statusCode == 401 && auth) {
      final refreshed = await _refreshSessionIfPossible();
      if (refreshed != null) {
        final retryHeaders = await _headers(auth: auth);
        final retry = await _send(_executeRequest(uri, method, retryHeaders, body));
        return _decodeResponse(retry);
      }
    }
    return _decodeResponse(response);
  }

  Future<AuthSession?> _refreshSessionIfPossible() async {
    final current = await tokenStore.loadSession();
    if (current == null || current.refreshToken.trim().isEmpty) {
      await tokenStore.clear();
      return null;
    }

    try {
      final refreshUri = Uri.parse('$baseUrl/auth/refresh');
      final refreshResponse = await _send(
        _client.post(
          refreshUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': current.refreshToken}),
        ),
      );
      final payload = _decodeResponse(refreshResponse);
      final userId = payload['user_id']?.toString();
      final accessToken = payload['access_token']?.toString();
      final refreshToken = payload['refresh_token']?.toString();
      if (userId == null || accessToken == null || refreshToken == null) {
        await tokenStore.clear();
        return null;
      }
      final nextSession = AuthSession(
        userId: userId,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await tokenStore.saveSession(nextSession);
      return nextSession;
    } catch (_) {
      await tokenStore.clear();
      return null;
    }
  }

  Future<http.Response> _executeRequest(
    Uri uri,
    String method,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) {
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri,
            headers: headers, body: jsonEncode(body ?? const {}));
      case 'PATCH':
        return _client.patch(uri,
            headers: headers, body: jsonEncode(body ?? const {}));
      default:
        return _client.get(uri, headers: headers);
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
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
