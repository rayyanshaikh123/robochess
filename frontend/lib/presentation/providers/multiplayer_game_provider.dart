import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/social_socket_client.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/multiplayer_game_model.dart';
import 'social_provider.dart';

/// Games the user is currently playing or has finished.
class GameListController
    extends StateNotifier<AsyncValue<List<MultiplayerGame>>> {
  final MultiplayerRepository _repository;
  final SocialSocketClient _socket;
  final String scope;
  StreamSubscription? _events;

  GameListController(this._repository, this._socket, this.scope)
      : super(const AsyncValue.loading()) {
    _events = _socket.stream.listen(_onEvent);
    load();
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (type == 'game.created' || type == 'game.over' || type == 'game.move') {
      load();
    }
  }

  Future<void> load() async {
    try {
      final games = await _repository.games(scope: scope);
      if (!mounted) return;
      state = AsyncValue.data(games);
    } catch (err, stack) {
      if (!mounted) return;
      state = AsyncValue.error(err, stack);
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}

final activeGamesProvider = StateNotifierProvider<GameListController,
    AsyncValue<List<MultiplayerGame>>>((ref) {
  return GameListController(
    ref.read(multiplayerRepositoryProvider),
    ref.read(socialSocketProvider),
    'active',
  );
});

final gameHistoryProvider = StateNotifierProvider<GameListController,
    AsyncValue<List<MultiplayerGame>>>((ref) {
  return GameListController(
    ref.read(multiplayerRepositoryProvider),
    ref.read(socialSocketProvider),
    'completed',
  );
});

/// One live game.
///
/// Every mutation goes to the server and the authoritative response replaces
/// local state; nothing about turn order, legality or results is decided here.
class MultiplayerGameController
    extends StateNotifier<AsyncValue<MultiplayerGame>> {
  final MultiplayerRepository _repository;
  final SocialSocketClient _socket;
  final String gameId;

  StreamSubscription? _events;
  StreamSubscription? _connection;

  final StreamController<String> _notices = StreamController<String>.broadcast();
  List<GameChatMessage> _chat = const [];
  bool _opponentOnline = false;
  bool _socketConnected = true;

  MultiplayerGameController(this._repository, this._socket, this.gameId)
      : super(const AsyncValue.loading()) {
    _events = _socket.stream.listen(_onEvent);
    _connection = _socket.connectionState.listen(_onConnectionChanged);
    _init();
  }

  /// One-shot messages for the UI to surface (draw offers, disconnects...).
  Stream<String> get notices => _notices.stream;
  List<GameChatMessage> get chat => _chat;
  bool get opponentOnline => _opponentOnline;
  bool get socketConnected => _socketConnected;

  Future<void> _init() async {
    await load();
    final version = state.valueOrNull?.gameVersion ?? -1;
    // Joining the room is what authorises this socket for the game and gets us
    // a delta for anything missed while the screen was closed.
    await _socket.connect(gameId: gameId, lastKnownVersion: version);
    await loadChat();
  }

  void _onConnectionChanged(bool connected) {
    _socketConnected = connected;
    if (connected) {
      // Reconnected: take the server's word for the current position rather
      // than resuming from whatever the screen still had.
      refresh();
    } else {
      _emit('Connection lost. Reconnecting...');
      _rebuild();
    }
  }

  /// Re-emit the current game so widgets reading the controller's plain fields
  /// (chat, presence, connectivity) rebuild.
  void _rebuild() {
    final current = state.valueOrNull;
    if (mounted && current != null) state = AsyncValue.data(current);
  }

  void _emit(String message) {
    if (!_notices.isClosed) _notices.add(message);
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    final data = event['data'];
    final payload = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};

    switch (type) {
      case 'game.move':
        if (payload['game_id'] != gameId) return;
        final version = payload['game_version'];
        if (version is int) _socket.noteVersion(version);
        refresh();
        break;
      case 'game.state':
      case 'game.delta':
      case 'game.up_to_date':
        if (payload['game_id'] != gameId) return;
        refresh();
        break;
      case 'game.over':
        if (payload['game_id'] != gameId) return;
        refresh();
        break;
      case 'game.draw.offered':
        if (payload['game_id'] != gameId) return;
        _emit('Your opponent offered a draw.');
        refresh();
        break;
      case 'game.draw.rejected':
        if (payload['game_id'] != gameId) return;
        _emit('Draw offer declined.');
        refresh();
        break;
      case 'game.draw.accepted':
        if (payload['game_id'] != gameId) return;
        refresh();
        break;
      case 'game.chat':
        if (payload['game_id'] != gameId) return;
        _chat = [..._chat, GameChatMessage.fromJson(payload)];
        _rebuild();
        break;
      case 'player.joined':
      case 'player.left':
        if (payload['game_id'] != gameId) return;
        final who = payload['user_id']?.toString();
        final opponentId = state.valueOrNull?.opponent.userId;
        if (who != null && who == opponentId) {
          _opponentOnline = type == 'player.joined';
          _emit(_opponentOnline
              ? 'Your opponent reconnected.'
              : 'Your opponent disconnected.');
          _rebuild();
        }
        break;
    }
  }

  Future<void> load() async {
    try {
      final game = await _repository.game(gameId);
      if (!mounted) return;
      _socket.noteVersion(game.gameVersion);
      state = AsyncValue.data(game);
    } catch (err, stack) {
      if (!mounted) return;
      state = AsyncValue.error(err, stack);
    }
  }

  /// Reload without dropping the current board to a spinner.
  Future<void> refresh() async {
    try {
      final game = await _repository.game(gameId);
      if (!mounted) return;
      _socket.noteVersion(game.gameVersion);
      state = AsyncValue.data(game);
    } catch (_) {
      // Keep showing the last good state; the socket will nudge us again.
    }
  }

  Future<void> loadChat() async {
    try {
      final messages = await _repository.chat(gameId);
      if (!mounted) return;
      _chat = messages;
      _rebuild();
    } catch (_) {
      // Chat is non-essential; failing to load it must not break the game.
    }
  }

  Future<void> submitMove(String uci) async {
    final current = state.valueOrNull;
    final game = await _repository.submitMove(
      gameId: gameId,
      uci: uci,
      expectedVersion: current?.gameVersion,
    );
    if (!mounted) return;
    _socket.noteVersion(game.gameVersion);
    state = AsyncValue.data(game);
  }

  Future<void> resign() async {
    final game = await _repository.resign(gameId);
    if (!mounted) return;
    state = AsyncValue.data(game);
  }

  Future<void> offerDraw() async {
    final game = await _repository.offerDraw(gameId);
    if (!mounted) return;
    state = AsyncValue.data(game);
  }

  Future<void> respondToDraw(bool accept) async {
    final game = await _repository.respondToDraw(gameId, accept);
    if (!mounted) return;
    state = AsyncValue.data(game);
  }

  Future<void> sendChat(String text) async {
    final message = await _repository.sendChat(gameId, text);
    if (!mounted) return;
    _chat = [..._chat, message];
    _rebuild();
  }

  @override
  void dispose() {
    _events?.cancel();
    _connection?.cancel();
    _notices.close();
    super.dispose();
  }
}

final multiplayerGameProvider = StateNotifierProvider.family<
    MultiplayerGameController, AsyncValue<MultiplayerGame>, String>((ref, gameId) {
  return MultiplayerGameController(
    ref.read(multiplayerRepositoryProvider),
    ref.read(socialSocketProvider),
    gameId,
  );
});
