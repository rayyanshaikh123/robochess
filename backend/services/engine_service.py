import chess
import chess.engine
from typing import Optional


def get_ai_move(
    board: chess.Board,
    engine: chess.engine.SimpleEngine,
    difficulty: int,
    base_time: float,
) -> chess.Move:
    if engine is None:
        raise RuntimeError("Engine not available")
    difficulty = max(1, min(10, int(difficulty)))
    
    # Map 1-10 difficulty to Stockfish Skill Level 0-20
    skill_level = int((difficulty - 1) * (20 / 9))
    engine.configure({"Skill Level": skill_level})
    
    time_limit = max(0.1, float(base_time) * (0.4 + (difficulty / 10.0)))
    result = engine.play(board, chess.engine.Limit(time=time_limit))
    if result.move is None:
        raise RuntimeError("Engine returned no move")
    return result.move


def analyze_position(
    board: chess.Board,
    engine: chess.engine.SimpleEngine,
    time_limit: float = 0.1,
) -> dict:
    """
    Evaluate a position and return the centipawn score and the best move.

    Returns dict with keys:
      - score_cp: int  (centipawns from White's perspective, ±9999 for mate)
      - best_move: str | None  (UCI string of the engine's preferred move)
    """
    if engine is None:
        return {"score_cp": 0, "best_move": None}

    info = engine.analyse(
        board,
        chess.engine.Limit(time=time_limit),
        info=chess.engine.INFO_SCORE | chess.engine.INFO_PV,
    )

    # Extract score from White's perspective
    score = info.get("score")
    if score is None:
        score_cp = 0
    else:
        pov = score.white()
        if pov.is_mate():
            mate_in = pov.mate()
            score_cp = 9999 if mate_in > 0 else -9999
        else:
            score_cp = pov.score()

    # Extract best move from PV
    pv = info.get("pv", [])
    best_move = pv[0].uci() if pv else None

    return {"score_cp": score_cp, "best_move": best_move}
