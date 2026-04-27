try:
    from backend.board_recognizer import BoardRecognizer
except ImportError:
    from board_recognizer import BoardRecognizer
from backend.core.config import Settings


def validate_initial_board(
    board_state: dict[str, str],
    recognizer: BoardRecognizer,
    settings: Settings,
) -> tuple[bool, list[str]]:
    return recognizer.validate_initial_state(
        board_state,
        max_missing=settings.start_max_missing,
        max_extra=settings.start_max_extra,
    )
