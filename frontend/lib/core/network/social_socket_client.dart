import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'token_store.dart';

/// Authenticated socket for social and multiplayer events.
///
/// Unlike [GameSocketClient] this one sends the access token (the server needs
/// it to place the connection in the user's room and to authorise a private
/// game room) and reconnects on its own with backoff. On every reconnect it
/// re-sends `hello` with the last version it saw, so the server replies with a
/// delta or a full snapshot and the client never resumes from stale state.
class SocialSocketClient {
  final String wsBaseUrl;
  final TokenStore tokenStore;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  String? _gameId;
  int _lastKnownVersion = -1;
  int _attempt = 0;
  bool _closed = false;
  bool _connected = false;

  static const _maxBackoff = Duration(seconds: 30);
  static const _heartbeatInterval = Duration(seconds: 25);

  SocialSocketClient({required this.wsBaseUrl, required this.tokenStore});

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  /// Emits true when the socket is live, false when it drops.
  Stream<bool> get connectionState => _connectionController.stream;

  bool get isConnected => _connected;

  Future<void> connect({String? gameId, int lastKnownVersion = -1}) async {
    _closed = false;
    if (gameId != null) {
      _gameId = gameId;
      _lastKnownVersion = lastKnownVersion;
    }
    await _open();
  }

  /// Track the newest version we have applied, so a reconnect resyncs from it.
  void noteVersion(int version) {
    if (version > _lastKnownVersion) _lastKnownVersion = version;
  }

  Future<void> _open() async {
    await _subscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Closing an already-broken socket is not an error worth surfacing.
    }

    try {
      final session = await tokenStore.loadSession();
      final uri = Uri.parse(wsBaseUrl).replace(queryParameters: {
        if (session != null) 'access_token': session.accessToken,
      });
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _setConnected(true);
      _attempt = 0;
      _startHeartbeat();
      _sendHello();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic event) {
    try {
      final decoded = jsonDecode(event as String);
      if (decoded is Map<String, dynamic>) {
        _controller.add(decoded);
      }
    } catch (_) {
      // A malformed frame should not tear down the connection.
    }
  }

  void _sendHello() {
    final gameId = _gameId;
    if (gameId == null || gameId.isEmpty) return;
    _send({
      'type': 'hello',
      'game_id': gameId,
      'last_known_version': _lastKnownVersion,
    });
  }

  /// Ask the server for anything missed since [_lastKnownVersion].
  void resync() {
    final gameId = _gameId;
    if (gameId == null || gameId.isEmpty) return;
    _send({
      'type': 'resync',
      'game_id': gameId,
      'last_known_version': _lastKnownVersion,
    });
  }

  void joinGame(String gameId, {int lastKnownVersion = -1}) {
    _gameId = gameId;
    _lastKnownVersion = lastKnownVersion;
    _sendHello();
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _send({'type': 'ping'});
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectionController.isClosed) _connectionController.add(value);
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _heartbeatTimer?.cancel();
    _setConnected(false);
    if (_reconnectTimer?.isActive ?? false) return;

    // 1s, 2s, 4s ... capped, so a long outage does not hammer the server.
    final seconds = 1 << (_attempt.clamp(0, 5));
    final delay = Duration(seconds: seconds) > _maxBackoff
        ? _maxBackoff
        : Duration(seconds: seconds);
    _attempt += 1;
    _reconnectTimer = Timer(delay, () {
      if (!_closed) _open();
    });
  }

  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Ignore: we are tearing down anyway.
    }
    _setConnected(false);
  }

  Future<void> dispose() async {
    await close();
    await _controller.close();
    await _connectionController.close();
  }
}
