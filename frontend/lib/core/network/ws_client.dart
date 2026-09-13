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

    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsBaseUrl));
      channel.ready.catchError((_) {
        // Suppress unhandled socket connect timeout
      });
      _channel = channel;
      _subscription = channel.stream.listen(
        (event) {
          try {
            final data = jsonDecode(event as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {}
        },
        onError: (err) {
          // Gracefully absorb connection / socket error
        },
        onDone: () {},
        cancelOnError: false,
      );

      // Attempt initial hello if channel exists
      try {
        _channel?.sink.add(jsonEncode({
          'type': 'hello',
          'game_id': gameId,
          'last_known_version': lastKnownVersion,
        }));
      } catch (_) {}
    } catch (_) {
      // Gracefully handle connect failure
    }
  }

  void resync({required String gameId, required int lastKnownVersion}) {
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'resync',
        'game_id': gameId,
        'last_known_version': lastKnownVersion,
      }));
    } catch (_) {}
  }

  void ping() {
    try {
      _channel?.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {}
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

    try {
      final session = await tokenStore.loadSession();
      final uri = Uri.parse(wsBaseUrl).replace(queryParameters: {
        if (session != null) 'access_token': session.accessToken,
      });
      final channel = WebSocketChannel.connect(uri);
      channel.ready.catchError((_) {
        // Suppress unhandled socket connect timeout
      });
      _channel = channel;
      _subscription = channel.stream.listen(
        (event) {
          try {
            final data = jsonDecode(event as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {}
        },
        onError: (err) {
          // Gracefully absorb socket timeout / network unreachable error
        },
        onDone: () {},
        cancelOnError: false,
      );
    } catch (_) {
      // Connect failure caught gracefully
    }
  }

  void subscribe(List<String> deviceIds) {
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'device.subscribe',
        'device_ids': deviceIds,
      }));
    } catch (_) {}
  }

  void ping() {
    try {
      _channel?.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {}
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
  }
}
