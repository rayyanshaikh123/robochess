import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/game_repository.dart';
import '../../domain/models/game_state.dart';
import 'session_provider.dart';

class GameController extends StateNotifier<AsyncValue<GameStateModel?>> {
  final GameRepository _repository;

  GameController(this._repository) : super(const AsyncValue.data(null));

  Future<void> createGame({
    String mode = 'human_vs_ai',
    int difficulty = 5,
    List<String>? players,
  }) async {
    state = const AsyncValue.loading();
    final game = await _repository.createGame(
      mode: mode,
      difficulty: difficulty,
      players: players,
    );
    state = AsyncValue.data(game);
  }

  Future<void> refresh(String gameId) async {
    state = const AsyncValue.loading();
    final game = await _repository.gameState(gameId);
    state = AsyncValue.data(game);
  }

  Future<void> submitMove(
      {required String gameId,
      required String uci,
      int? expectedVersion}) async {
    state = const AsyncValue.loading();
    final game = await _repository.submitMove(
      gameId: gameId,
      uci: uci,
      expectedVersion: expectedVersion,
    );
    state = AsyncValue.data(game);
  }

  Future<void> undoMove() async {
    // We don't necessarily need to set state to loading if we want the WS
    // to handle the actual state update, but it's safe to do so.
    await _repository.undoMove();
  }

  Future<void> resignGame(String gameId) async {
    await _repository.resignGame(gameId);
    // Refresh so the game-over status from the backend is reflected locally.
    await refresh(gameId);
  }
}

final gameControllerProvider =
    StateNotifierProvider<GameController, AsyncValue<GameStateModel?>>((ref) {
  return GameController(ref.read(gameRepositoryProvider));
});
