from typing import Optional

import chess

try:
    from backend.board_recognizer import BoardRecognizer
except ImportError:
    from board_recognizer import BoardRecognizer
from backend.core.config import Settings


def detect_move(
    prev_state: dict[str, Optional[str]],
    curr_state: dict[str, Optional[str]],
    chess_board: chess.Board,
    recognizer: BoardRecognizer,
    settings: Settings,
) -> tuple[Optional[chess.Move], int, int]:
    return recognizer.infer_move_from_state(
        chess_board,
        curr_state,
        min_score=settings.move_match_min_score,
        min_gap=settings.move_match_min_gap,
    )
