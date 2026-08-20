import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'token_store.dart';

class GameSocketClient {
  final String wsBaseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  GameSocketClient({required this.wsBaseUrl});

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Future<void> connect(
      {required String gameId, required int lastKnownVersion}) async {
    await _subscription?.cancel();
    await _channel?.sink.close();

    _channel = WebSocketChannel.connect(Uri.parse(wsBaseUrl));
    _subscription = _channel!.stream.listen((event) {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      _controller.add(data);
    });
    _channel!.sink.add(jsonEncode({
      'type': 'hello',
      'game_id': gameId,
      'last_known_version': lastKnownVersion,
    }));
  }

  void resync({required String gameId, required int lastKnownVersion}) {
    _channel?.sink.add(jsonEncode({
      'type': 'resync',
      'game_id': gameId,
      'last_known_version': lastKnownVersion,
    }));
  }

  void ping() {
    _channel?.sink.add(jsonEncode({'type': 'ping'}));
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
  }
}

class DeviceSocketClient {
  final String wsBaseUrl;
  final TokenStore tokenStore;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  DeviceSocketClient({required this.wsBaseUrl, required this.tokenStore});

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Future<void> connect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();

    final session = await tokenStore.loadSession();
    final uri = Uri.parse(wsBaseUrl).replace(queryParameters: {
      if (session != null) 'access_token': session.accessToken,
    });
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen((event) {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      _controller.add(data);
    });
  }

  void subscribe(List<String> deviceIds) {
    _channel?.sink.add(jsonEncode({
      'type': 'device.subscribe',
      'device_ids': deviceIds,
    }));
  }

  void ping() {
    _channel?.sink.add(jsonEncode({'type': 'ping'}));
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
  }
}
