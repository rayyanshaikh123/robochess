import '../../core/network/api_client.dart';
import '../../domain/models/puzzle_attempt.dart';
import '../../domain/models/puzzle_model.dart';

class PuzzleRemoteDataSource {
  final ApiClient _client;

  PuzzleRemoteDataSource(this._client);

  Future<List<PuzzleModel>> list({int limit = 20}) async {
    final data = await _client.getJson('/puzzles/list', queryParameters: {
      'limit': limit.toString(),
    });
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => PuzzleModel.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<PuzzleAttemptResult> attempt({
    required String puzzleId,
    required String uci,
    required int moveIndex,
  }) async {
    final data = await _client.postJson('/puzzles/attempt', body: {
      'puzzle_id': puzzleId,
      'uci': uci,
      'move_index': moveIndex,
    });
    return PuzzleAttemptResult.fromJson(data);
  }
}
