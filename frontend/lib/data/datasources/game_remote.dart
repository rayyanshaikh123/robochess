import '../../core/network/api_client.dart';
import '../../domain/models/game_state.dart';

class GameRemoteDataSource {
  final ApiClient _client;

  GameRemoteDataSource(this._client);

  Future<GameStateModel> createGame({
    String mode = 'human_vs_ai',
    int difficulty = 5,
    List<String>? players,
  }) async {
    final data = await _client.postJson('/game/start', body: {
      'mode': mode,
      'difficulty': difficulty,
      if (players != null) 'players': players,
    });
    return GameStateModel.fromJson(data);
  }

  Future<GameStateModel> gameState(String gameId) async {
    final data = await _client
        .getJson('/game/state', queryParameters: {'game_id': gameId});
    return GameStateModel.fromJson(data);
  }

  Future<GameStateModel> submitMove({
    required String gameId,
    required String uci,
    int? expectedVersion,
  }) async {
    final data = await _client.postJson('/game/move', body: {
      'game_id': gameId,
      'uci': uci,
      'expected_version': expectedVersion,
    });
    return GameStateModel.fromJson(data);
  }
}
