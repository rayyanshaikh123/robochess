import '../../domain/models/challenge_model.dart';
import '../../domain/models/friend_model.dart';
import '../../domain/models/multiplayer_game_model.dart';
import '../datasources/social_remote.dart';

class FriendsRepository {
  final FriendsRemoteDataSource _remote;
  FriendsRepository(this._remote);

  Future<List<FriendModel>> friends() => _remote.friends();
  Future<List<FriendModel>> incomingRequests() => _remote.incomingRequests();
  Future<List<FriendModel>> outgoingRequests() => _remote.outgoingRequests();
  Future<List<UserSearchResult>> search(String query) => _remote.search(query);
  Future<void> sendRequest(String userId) => _remote.sendRequest(userId);
  Future<void> acceptRequest(String id) => _remote.acceptRequest(id);
  Future<void> rejectRequest(String id) => _remote.rejectRequest(id);
  Future<void> cancelRequest(String id) => _remote.cancelRequest(id);
  Future<void> removeFriend(String userId) => _remote.removeFriend(userId);
}

class ChallengesRepository {
  final ChallengesRemoteDataSource _remote;
  ChallengesRepository(this._remote);

  Future<List<TimeControlOption>> timeControls() => _remote.timeControls();
  Future<List<ChallengeModel>> incoming() => _remote.incoming();
  Future<List<ChallengeModel>> outgoing() => _remote.outgoing();

  Future<ChallengeModel> create({
    required String opponentId,
    String? timeControl,
    String surface = 'app',
    String color = 'random',
  }) =>
      _remote.create(
        opponentId: opponentId,
        timeControl: timeControl,
        surface: surface,
        color: color,
      );

  Future<String> accept(String challengeId, {String surface = 'app'}) =>
      _remote.accept(challengeId, surface: surface);
  Future<void> reject(String challengeId) => _remote.reject(challengeId);
  Future<void> cancel(String challengeId) => _remote.cancel(challengeId);
  Future<ChallengeModel> rematch(String gameId) => _remote.rematch(gameId);
}

class MultiplayerRepository {
  final MultiplayerRemoteDataSource _remote;
  MultiplayerRepository(this._remote);

  Future<List<MultiplayerGame>> games({String scope = 'active'}) =>
      _remote.games(scope: scope);
  Future<MultiplayerGame> game(String gameId) => _remote.game(gameId);

  Future<MultiplayerGame> submitMove({
    required String gameId,
    required String uci,
    int? expectedVersion,
  }) =>
      _remote.submitMove(
        gameId: gameId,
        uci: uci,
        expectedVersion: expectedVersion,
      );

  Future<MultiplayerGame> resign(String gameId) => _remote.resign(gameId);
  Future<MultiplayerGame> offerDraw(String gameId) => _remote.offerDraw(gameId);
  Future<MultiplayerGame> respondToDraw(String gameId, bool accept) =>
      _remote.respondToDraw(gameId, accept);
  Future<List<GameChatMessage>> chat(String gameId) => _remote.chat(gameId);
  Future<GameChatMessage> sendChat(String gameId, String text) =>
      _remote.sendChat(gameId, text);
}
