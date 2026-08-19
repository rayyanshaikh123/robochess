import os
import threading
import time
from typing import Optional

import chess
import chess.engine
import cv2
import numpy as np

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
        
        # Auto-detection state
        self.auto_detect_enabled = False
        self.auto_detect_stop = threading.Event()
        self.auto_detect_thread: Optional[threading.Thread] = None
        self.last_auto_detect_time = 0.0
        self.last_auto_detect_result: Optional[dict] = None

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
        self.stop_auto_detect()

    def detect_hand_motion(self, frame: np.ndarray) -> bool:
        """Detect hand motion using frame differencing. Returns True if motion detected."""
        MOTION_DIFF_THRESHOLD = 20  # Pixels with > 20 intensity difference
        MOTION_BLUR = 7
        MOTION_RATIO_TRIGGER = 0.02  # 2% of pixels changed
        
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if MOTION_BLUR > 0:
            gray = cv2.GaussianBlur(gray, (MOTION_BLUR, MOTION_BLUR), 0)
        
        if self.hand_prev_gray is None or self.hand_prev_gray.shape != gray.shape:
            self.hand_prev_gray = gray
            return False
        
        diff = cv2.absdiff(self.hand_prev_gray, gray)
        _, thresh = cv2.threshold(diff, MOTION_DIFF_THRESHOLD, 255, cv2.THRESH_BINARY)
        motion_ratio = float(np.count_nonzero(thresh)) / float(thresh.size)
        self.hand_prev_gray = gray
        
        return motion_ratio >= MOTION_RATIO_TRIGGER

    def should_auto_detect(self) -> bool:
        """Check if conditions are met for auto-detection (hand absent for threshold time)."""
        if not self.auto_detect_enabled or self.prev_state is None:
            return False
        
        try:
            frame = self.capture_frame()
            has_motion = self.detect_hand_motion(frame)
        except Exception:
            return False
        
        now = time.time()
        if has_motion:
            self.hand_last_seen = now
            self.hand_present = True
            return False
        
        # Hand not present; check if absent long enough
        hand_absence_threshold = float(self.settings.hand_absence_seconds)
        hand_cooldown = float(self.settings.hand_trigger_cooldown_seconds)
        
        if (now - self.hand_last_seen) >= hand_absence_threshold:
            # Check cooldown
            if (now - self.last_auto_detect_time) >= hand_cooldown:
                return True
        
        return False

    def start_auto_detect(self) -> None:
        """Start the auto-detection background thread."""
        if self.auto_detect_enabled or self.auto_detect_thread and self.auto_detect_thread.is_alive():
            return
        self.auto_detect_enabled = True
        self.auto_detect_stop.clear()
        self.auto_detect_thread = threading.Thread(target=self._auto_detect_loop, daemon=True)
        self.auto_detect_thread.start()

    def stop_auto_detect(self) -> None:
        """Stop the auto-detection background thread."""
        self.auto_detect_enabled = False
        self.auto_detect_stop.set()
        if self.auto_detect_thread and self.auto_detect_thread.is_alive():
            self.auto_detect_thread.join(timeout=2.0)

    def _auto_detect_loop(self) -> None:
        """Background loop that triggers move analysis when hand is absent."""
        while not self.auto_detect_stop.is_set():
            try:
                if self.should_auto_detect():
                    self.last_auto_detect_time = time.time()
                    # Signal that auto-detect is ready; the API will call analyze_move_snapshot
                    with self.state_lock:
                        self.hand_present = False
            except Exception:
                pass
            time.sleep(0.1)

