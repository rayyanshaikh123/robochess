import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/server_config_provider.dart';
import '../../core/network/social_socket_client.dart';
import '../../data/datasources/social_remote.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/challenge_model.dart';
import '../../domain/models/friend_model.dart';
import 'session_provider.dart';

// ── Wiring ────────────────────────────────────────────────────────────────────

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  return FriendsRepository(FriendsRemoteDataSource(ref.read(apiClientProvider)));
});

final challengesRepositoryProvider = Provider<ChallengesRepository>((ref) {
  return ChallengesRepository(
      ChallengesRemoteDataSource(ref.read(apiClientProvider)));
});

final multiplayerRepositoryProvider = Provider<MultiplayerRepository>((ref) {
  return MultiplayerRepository(
      MultiplayerRemoteDataSource(ref.read(apiClientProvider)));
});

/// One authenticated socket shared by every social surface, so friend and
/// challenge events keep arriving regardless of which screen is open.
final socialSocketProvider = Provider<SocialSocketClient>((ref) {
  final httpBase = ref.watch(serverConfigProvider);
  final wsBase = '${httpBase.replaceFirst(RegExp(r'^https://'), 'wss://').replaceFirst(RegExp(r'^http://'), 'ws://')}/ws';
  final client = SocialSocketClient(
    wsBaseUrl: wsBase,
    tokenStore: ref.read(tokenStoreProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

final timeControlsProvider = FutureProvider<List<TimeControlOption>>((ref) {
  return ref.read(challengesRepositoryProvider).timeControls();
});

// ── Friends ───────────────────────────────────────────────────────────────────

/// Friends, incoming and outgoing requests, kept in one place because every
/// mutation moves a row between the three lists.
class FriendsState {
  final List<FriendModel> friends;
  final List<FriendModel> incoming;
  final List<FriendModel> outgoing;

  const FriendsState({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });
}

class FriendsController extends StateNotifier<AsyncValue<FriendsState>> {
  final FriendsRepository _repository;
  final SocialSocketClient _socket;
  StreamSubscription? _events;

  FriendsController(this._repository, this._socket)
      : super(const AsyncValue.loading()) {
    _events = _socket.stream.listen(_onEvent);
    load();
  }

  static const _refreshEvents = {
    'friend.request.received',
    'friend.request.accepted',
    'friend.request.rejected',
    'friend.request.cancelled',
    'friend.removed',
  };

  void _onEvent(Map<String, dynamic> event) {
    // The server is the source of truth for these lists, so a nudge to reload
    // is simpler and safer than patching three lists from a partial payload.
    if (_refreshEvents.contains(event['type'])) load();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        _repository.friends(),
        _repository.incomingRequests(),
        _repository.outgoingRequests(),
      ]);
      if (!mounted) return;
      state = AsyncValue.data(FriendsState(
        friends: results[0],
        incoming: results[1],
        outgoing: results[2],
      ));
    } catch (err, stack) {
      if (!mounted) return;
      state = AsyncValue.error(err, stack);
    }
  }

  Future<void> sendRequest(String userId) async {
    await _repository.sendRequest(userId);
    await load();
  }

  Future<void> acceptRequest(String friendshipId) async {
    await _repository.acceptRequest(friendshipId);
    await load();
  }

  Future<void> rejectRequest(String friendshipId) async {
    await _repository.rejectRequest(friendshipId);
    await load();
  }

  Future<void> cancelRequest(String friendshipId) async {
    await _repository.cancelRequest(friendshipId);
    await load();
  }

  Future<void> removeFriend(String userId) async {
    await _repository.removeFriend(userId);
    await load();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}

final friendsProvider =
    StateNotifierProvider<FriendsController, AsyncValue<FriendsState>>((ref) {
  return FriendsController(
    ref.read(friendsRepositoryProvider),
    ref.read(socialSocketProvider),
  );
});

/// Search results, kept separate from [friendsProvider] so typing a query does
/// not disturb the lists.
class UserSearchController extends StateNotifier<AsyncValue<List<UserSearchResult>>> {
  final FriendsRepository _repository;
  String _query = '';

  UserSearchController(this._repository) : super(const AsyncValue.data([]));

  String get query => _query;

  Future<void> search(String query) async {
    _query = query;
    if (query.trim().length < 2) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final results = await _repository.search(query);
      if (!mounted || _query != query) return;
      state = AsyncValue.data(results);
    } catch (err, stack) {
      if (!mounted) return;
      state = AsyncValue.error(err, stack);
    }
  }

  void clear() {
    _query = '';
    state = const AsyncValue.data([]);
  }
}

final userSearchProvider =
    StateNotifierProvider<UserSearchController, AsyncValue<List<UserSearchResult>>>(
        (ref) {
  return UserSearchController(ref.read(friendsRepositoryProvider));
});

// ── Challenges ────────────────────────────────────────────────────────────────

class ChallengesState {
  final List<ChallengeModel> incoming;
  final List<ChallengeModel> outgoing;

  const ChallengesState({this.incoming = const [], this.outgoing = const []});
}

class ChallengesController extends StateNotifier<AsyncValue<ChallengesState>> {
  final ChallengesRepository _repository;
  final SocialSocketClient _socket;
  StreamSubscription? _events;

  /// Game ids created while this controller was alive, so a screen can offer to
  /// open a game the moment a challenge is accepted by either side.
  final StreamController<String> _gameStarted =
      StreamController<String>.broadcast();

  ChallengesController(this._repository, this._socket)
      : super(const AsyncValue.loading()) {
    _events = _socket.stream.listen(_onEvent);
    load();
  }

  Stream<String> get gameStarted => _gameStarted.stream;

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (type == 'game.created') {
      final data = event['data'];
      final gameId = data is Map ? data['game_id']?.toString() : null;
      if (gameId != null && gameId.isNotEmpty && !_gameStarted.isClosed) {
        _gameStarted.add(gameId);
      }
      load();
      return;
    }
    if (type == 'challenge.received' ||
        type == 'challenge.accepted' ||
        type == 'challenge.rejected' ||
        type == 'challenge.cancelled') {
      load();
    }
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        _repository.incoming(),
        _repository.outgoing(),
      ]);
      if (!mounted) return;
      state = AsyncValue.data(
          ChallengesState(incoming: results[0], outgoing: results[1]));
    } catch (err, stack) {
      if (!mounted) return;
      state = AsyncValue.error(err, stack);
    }
  }

  Future<ChallengeModel> create({
    required String opponentId,
    String? timeControl,
    String surface = 'app',
    String color = 'random',
  }) async {
    final challenge = await _repository.create(
      opponentId: opponentId,
      timeControl: timeControl,
      surface: surface,
      color: color,
    );
    await load();
    return challenge;
  }

  /// Returns the id of the game the accepted challenge created.
  Future<String> accept(String challengeId, {String surface = 'app'}) async {
    final gameId = await _repository.accept(challengeId, surface: surface);
    await load();
    return gameId;
  }

  Future<void> reject(String challengeId) async {
    await _repository.reject(challengeId);
    await load();
  }

  Future<void> cancel(String challengeId) async {
    await _repository.cancel(challengeId);
    await load();
  }

  Future<ChallengeModel> rematch(String gameId) async {
    final challenge = await _repository.rematch(gameId);
    await load();
    return challenge;
  }

  @override
  void dispose() {
    _events?.cancel();
    _gameStarted.close();
    super.dispose();
  }
}

final challengesProvider =
    StateNotifierProvider<ChallengesController, AsyncValue<ChallengesState>>((ref) {
  return ChallengesController(
    ref.read(challengesRepositoryProvider),
    ref.read(socialSocketProvider),
  );
});
