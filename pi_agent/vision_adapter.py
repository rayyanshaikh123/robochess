from typing import Optional, Tuple


class VisionAdapter:
    def __init__(self) -> None:
        pass

    def detect_move(self) -> Tuple[Optional[str], Optional[int]]:
        # Integrate your existing detection pipeline here.
        # Return (uci_move, expected_game_version) when a valid move is detected.
        return None, None
