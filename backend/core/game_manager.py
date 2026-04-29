import os
import threading
from typing import Optional

import chess
import chess.engine
import cv2

try:
    from backend.board_recognizer import BoardRecognizer
except ImportError:
    from board_recognizer import BoardRecognizer
from backend.core.config import Settings, load_settings


class GameManager:
    _instance: Optional["GameManager"] = None
    _singleton_lock = threading.Lock()

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.state_lock = threading.RLock()
        self.board = chess.Board()
        self.prev_state: Optional[dict[str, Optional[str]]] = None
        self.calibrated = False
        self.mode = "human_vs_ai"
        self.difficulty = 5
        self.current_game_id: Optional[str] = None
        self.hand_prev_gray = None
        self.hand_present = False
        self.hand_last_seen = 0.0
        self.last_capture_time = 0.0
        self.recapture_until = 0.0

        self.recognizer = BoardRecognizer(settings.model_path, confidence=settings.confidence)
        self.engine = self._load_engine(settings.stockfish_path)
        self.camera = self._open_camera(settings.camera_index, settings.capture_width, settings.capture_height)

    @classmethod
    def get_instance(cls) -> "GameManager":
        with cls._singleton_lock:
            if cls._instance is None:
                cls._instance = cls(load_settings())
        return cls._instance

    def _open_camera(self, camera_index: int, width: int, height: int) -> Optional[cv2.VideoCapture]:
        backends = [cv2.CAP_ANY]
        if os.name == "nt":
            backends = [cv2.CAP_DSHOW, cv2.CAP_MSMF, cv2.CAP_ANY]
        for backend in backends:
            capture = cv2.VideoCapture(camera_index, backend)
            if capture.isOpened():
                capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
                capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
                capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                return capture
            capture.release()
        return None

    def _load_engine(self, path: str) -> Optional[chess.engine.SimpleEngine]:
        if not path:
            return None
        try:
            return chess.engine.SimpleEngine.popen_uci(path)
        except Exception:
            return None

    def capture_frame(self):
        if self.camera is None or not self.camera.isOpened():
            raise RuntimeError("Camera not ready")
        ok, frame = self.camera.read()
        if not ok or frame is None or frame.size == 0:
            raise RuntimeError("Failed to capture frame")
        return frame

    def reset_game(self, keep_calibration: bool = True) -> None:
        with self.state_lock:
            self.board.reset()
            self.prev_state = None
            if not keep_calibration:
                self.calibrated = False

    def update_board(self, move: chess.Move) -> None:
        with self.state_lock:
            self.board.push(move)

    def get_fen(self) -> str:
        with self.state_lock:
            return self.board.fen()

    def close(self) -> None:
        if self.camera is not None:
            try:
                self.camera.release()
            except Exception:
                pass
        if self.engine is not None:
            try:
                self.engine.quit()
            except Exception:
                pass
