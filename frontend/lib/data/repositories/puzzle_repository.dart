import '../../domain/models/puzzle_attempt.dart';
import '../../domain/models/puzzle_model.dart';
import '../datasources/puzzle_remote.dart';

class PuzzleRepository {
  final PuzzleRemoteDataSource _remote;

  PuzzleRepository(this._remote);

  Future<List<PuzzleModel>> list({int limit = 20}) =>
      _remote.list(limit: limit);

  Future<PuzzleAttemptResult> attempt({
    required String puzzleId,
    required String uci,
    required int moveIndex,
  }) {
    return _remote.attempt(puzzleId: puzzleId, uci: uci, moveIndex: moveIndex);
  }
}
