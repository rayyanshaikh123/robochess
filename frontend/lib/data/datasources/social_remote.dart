import '../../core/network/api_client.dart';
import '../../domain/models/challenge_model.dart';
import '../../domain/models/friend_model.dart';
import '../../domain/models/multiplayer_game_model.dart';

/// Friends, requests and user search.
class FriendsRemoteDataSource {
  final ApiClient _client;
  FriendsRemoteDataSource(this._client);

  List<T> _items<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = data['items'];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((item) => parse(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<FriendModel>> friends() async {
    final data = await _client.getJson('/friends/list');
    return _items(data, FriendModel.fromJson);
  }

  Future<List<FriendModel>> incomingRequests() async {
    final data = await _client.getJson('/friends/requests/incoming');
    return _items(data, FriendModel.fromJson);
  }

  Future<List<FriendModel>> outgoingRequests() async {
    final data = await _client.getJson('/friends/requests/outgoing');
    return _items(data, FriendModel.fromJson);
  }

  Future<List<UserSearchResult>> search(String query) async {
    final data = await _client
        .getJson('/friends/search', queryParameters: {'q': query});
    return _items(data, UserSearchResult.fromJson);
  }

  Future<void> sendRequest(String userId) async {
    await _client.postJson('/friends/request', body: {'user_id': userId});
  }

  Future<void> acceptRequest(String friendshipId) async {
    await _client.postJson('/friends/requests/$friendshipId/accept', body: {});
  }

  Future<void> rejectRequest(String friendshipId) async {
    await _client.postJson('/friends/requests/$friendshipId/reject', body: {});
  }

  Future<void> cancelRequest(String friendshipId) async {
    await _client.postJson('/friends/requests/$friendshipId/cancel', body: {});
  }

  Future<void> removeFriend(String userId) async {
    await _client.postJson('/friends/remove', body: {'user_id': userId});
  }
}

/// Game challenges.
class ChallengesRemoteDataSource {
  final ApiClient _client;
  ChallengesRemoteDataSource(this._client);

  List<T> _items<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = data['items'];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((item) => parse(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<TimeControlOption>> timeControls() async {
    final data = await _client.getJson('/challenges/time-controls');
    return _items(data, TimeControlOption.fromJson);
  }

  Future<List<ChallengeModel>> incoming() async {
    final data = await _client.getJson('/challenges/incoming');
    return _items(data, ChallengeModel.fromJson);
  }

  Future<List<ChallengeModel>> outgoing() async {
    final data = await _client.getJson('/challenges/outgoing');
    return _items(data, ChallengeModel.fromJson);
  }

  Future<ChallengeModel> create({
    required String opponentId,
    String? timeControl,
    String surface = 'app',
    String color = 'random',
  }) async {
    final data = await _client.postJson('/challenges/create', body: {
      'opponent_id': opponentId,
      'time_control': timeControl,
      'surface': surface,
      'color': color,
    });
    return ChallengeModel.fromJson(data);
  }

  /// Returns the id of the game the challenge created.
  Future<String> accept(String challengeId, {String surface = 'app'}) async {
    final data = await _client.postJson(
      '/challenges/$challengeId/accept',
      body: {'surface': surface},
    );
    return data['game_id']?.toString() ?? '';
  }

  Future<void> reject(String challengeId) async {
    await _client.postJson('/challenges/$challengeId/reject', body: {});
  }

  Future<void> cancel(String challengeId) async {
    await _client.postJson('/challenges/$challengeId/cancel', body: {});
  }

  Future<ChallengeModel> rematch(String gameId) async {
    final data =
        await _client.postJson('/challenges/rematch', body: {'game_id': gameId});
    return ChallengeModel.fromJson(data);
  }
}

/// Multiplayer games.
class MultiplayerRemoteDataSource {
  final ApiClient _client;
  MultiplayerRemoteDataSource(this._client);

  Future<List<MultiplayerGame>> games({String scope = 'active'}) async {
    final data = await _client
        .getJson('/multiplayer/games', queryParameters: {'scope': scope});
    final raw = data['items'];
    if (raw is! List) return <MultiplayerGame>[];
    return raw
        .whereType<Map>()
        .map((item) => MultiplayerGame.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<MultiplayerGame> game(String gameId) async {
    final data = await _client.getJson('/multiplayer/games/$gameId');
    return MultiplayerGame.fromJson(data);
  }

  Future<MultiplayerGame> submitMove({
    required String gameId,
    required String uci,
    int? expectedVersion,
  }) async {
    final data = await _client.postJson(
      '/multiplayer/games/$gameId/move',
      body: {'uci': uci, 'expected_version': expectedVersion},
    );
    return MultiplayerGame.fromJson(data);
  }

  Future<MultiplayerGame> resign(String gameId) async {
    final data =
        await _client.postJson('/multiplayer/games/$gameId/resign', body: {});
    return MultiplayerGame.fromJson(data);
  }

  Future<MultiplayerGame> offerDraw(String gameId) async {
    final data = await _client
        .postJson('/multiplayer/games/$gameId/draw/offer', body: {});
    return MultiplayerGame.fromJson(data);
  }

  Future<MultiplayerGame> respondToDraw(String gameId, bool accept) async {
    final data = await _client.postJson(
      '/multiplayer/games/$gameId/draw/respond',
      body: {'accept': accept},
    );
    return MultiplayerGame.fromJson(data);
  }

  Future<List<GameChatMessage>> chat(String gameId) async {
    final data = await _client.getJson('/multiplayer/games/$gameId/chat');
    final raw = data['items'];
    if (raw is! List) return <GameChatMessage>[];
    return raw
        .whereType<Map>()
        .map((item) => GameChatMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<GameChatMessage> sendChat(String gameId, String text) async {
    final data = await _client
        .postJson('/multiplayer/games/$gameId/chat', body: {'text': text});
    return GameChatMessage.fromJson(data);
  }
}
