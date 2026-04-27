from typing import Optional

from backend.core.game_manager import GameManager


def detect_board_state_from_frame(
    manager: GameManager,
    frame,
) -> tuple[dict[str, Optional[str]], int]:
    recognizer = manager.recognizer
    if recognizer is None or not recognizer.is_ready:
        raise RuntimeError("Model not ready")

    warped = recognizer.warp_frame(frame)
    detections = recognizer.detect(warped)
    conf_min = float(manager.settings.detection_confidence_min)
    filtered = [
        det for det in detections if float(det.get("confidence", 0.0)) >= conf_min
    ]
    state = recognizer.detections_to_state_dict(
        filtered,
        warped.shape[1],
        warped.shape[0],
        min_confidence=conf_min,
    )
    return state, len(filtered)


def detect_board_state(manager: GameManager) -> tuple[dict[str, Optional[str]], int]:
    frame = manager.capture_frame()
    return detect_board_state_from_frame(manager, frame)
