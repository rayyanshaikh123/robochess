import '../../domain/models/game_state.dart';
import '../../domain/models/analysis_model.dart';
import '../datasources/game_remote.dart';

class GameRepository {
  final GameRemoteDataSource _remote;

  GameRepository(this._remote);

  Future<GameStateModel> createGame({
    String mode = 'human_vs_ai',
    int difficulty = 5,
    List<String>? players,
  }) {
    return _remote.createGame(
      mode: mode,
      difficulty: difficulty,
      players: players,
    );
  }

  Future<GameStateModel> gameState(String gameId) => _remote.gameState(gameId);

  Future<GameStateModel> submitMove({
    required String gameId,
    required String uci,
    int? expectedVersion,
  }) {
    return _remote.submitMove(
        gameId: gameId, uci: uci, expectedVersion: expectedVersion);
  }

  Future<AnalysisReport> fetchAnalysis(String gameId) async {
    final data = await _remote.fetchAnalysis(gameId);
    return AnalysisReport.fromJson(data);
  }

  Future<void> undoMove() => _remote.undoMove();
}
