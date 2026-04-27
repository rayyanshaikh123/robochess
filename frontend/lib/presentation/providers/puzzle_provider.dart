import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/puzzle_remote.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../domain/models/puzzle_attempt.dart';
import '../../domain/models/puzzle_model.dart';
import 'session_provider.dart';

final puzzleRepositoryProvider = Provider<PuzzleRepository>((ref) {
  return PuzzleRepository(PuzzleRemoteDataSource(ref.read(apiClientProvider)));
});

class PuzzleController extends StateNotifier<AsyncValue<List<PuzzleModel>>> {
  final PuzzleRepository _repository;

  PuzzleController(this._repository) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({int limit = 20}) async {
    final items = await _repository.list(limit: limit);
    state = AsyncValue.data(items);
  }
}

final puzzleControllerProvider =
    StateNotifierProvider<PuzzleController, AsyncValue<List<PuzzleModel>>>(
        (ref) {
  return PuzzleController(ref.read(puzzleRepositoryProvider));
});

final puzzleAttemptProvider =
    FutureProvider.family<PuzzleAttemptResult, PuzzleAttemptInput>(
  (ref, input) async {
    return ref.read(puzzleRepositoryProvider).attempt(
          puzzleId: input.puzzleId,
          uci: input.uci,
          moveIndex: input.moveIndex,
        );
  },
);

class PuzzleAttemptInput {
  final String puzzleId;
  final String uci;
  final int moveIndex;

  PuzzleAttemptInput({
    required this.puzzleId,
    required this.uci,
    required this.moveIndex,
  });
}
