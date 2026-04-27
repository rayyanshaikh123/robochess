import chess
import chess.engine


def get_ai_move(
    board: chess.Board,
    engine: chess.engine.SimpleEngine,
    difficulty: int,
    base_time: float,
) -> chess.Move:
    if engine is None:
        raise RuntimeError("Engine not available")
    difficulty = max(1, min(10, int(difficulty)))
    time_limit = max(0.1, float(base_time) * (0.4 + (difficulty / 10.0)))
    result = engine.play(board, chess.engine.Limit(time=time_limit))
    if result.move is None:
        raise RuntimeError("Engine returned no move")
    return result.move
