"""Shared Pi camera capture and local board-state move detection."""

from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any


class PiCameraDetector:
    """Owns the camera and translates calibrated frames into legal UCI moves.

    Model inference is deliberately local-only.  If the model, NumPy, or
    Ultralytics is missing, camera preview still works and detection reports a
    useful status instead of taking down the local service.
    """

    def __init__(self, camera_index: int, width: int, height: int,
                 calibration_path: str | Path, model_path: str,
                 confidence: float = 0.10) -> None:
        self.camera_index = camera_index
        self.width, self.height = width, height
        self.calibration_path = Path(calibration_path)
        self.model_path = model_path.strip()
        self.confidence = confidence
        self._camera: Any = None
        self._lock = threading.Lock()
        self.recognizer: Any = None
        self.last_error: str | None = None
        self._load_recognizer()

    def _load_recognizer(self) -> None:
        if not self.model_path:
            self.last_error = "ROBOCHESS_MODEL_PATH is not configured"
            return
        try:
            from backend.board_recognizer import BoardRecognizer
            self.recognizer = BoardRecognizer(self.model_path, self.confidence)
            if not self.recognizer.is_ready:
                self.last_error = "Local model could not be loaded"
        except Exception as exc:
            self.last_error = str(exc)

    @property
    def model_available(self) -> bool:
        return bool(self.recognizer and self.recognizer.is_ready)

    @property
    def calibrated(self) -> bool:
        return bool(self._read_calibration().get("corners"))

    def _read_calibration(self) -> dict:
        try:
            return json.loads(self.calibration_path.read_text())
        except (OSError, ValueError):
            return {}

    def _apply_calibration(self) -> None:
        if not self.recognizer:
            return
        corners = self._read_calibration().get("corners")
        if corners and len(corners) == 4:
            self.recognizer.calibrate([(float(p[0]), float(p[1])) for p in corners])

    def capture_frame(self):
        try:
            import cv2
        except ImportError as exc:
            raise RuntimeError("OpenCV is not installed") from exc
        with self._lock:
            if self._camera is None or not self._camera.isOpened():
                self._camera = cv2.VideoCapture(self.camera_index)
                self._camera.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
                self._camera.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
            ok, frame = self._camera.read()
        if not ok:
            raise RuntimeError("Camera frame unavailable")
        return frame

    def preview_frame(self):
        frame = self.capture_frame()
        if self.recognizer:
            self._apply_calibration()
            return self.recognizer.warp_frame(frame) if self.calibrated else frame
        return frame

    def status(self) -> dict:
        return {
            "model_available": self.model_available,
            "calibrated": self.calibrated,
            "model_path_configured": bool(self.model_path),
            "last_error": self.last_error,
        }

    def detect_candidates(self, session) -> list[str]:
        if not session or not self.model_available:
            return []
        if not self.calibrated:
            self.last_error = "Board is not calibrated"
            return []
        try:
            self._apply_calibration()
            frame = self.capture_frame()
            warped = self.recognizer.warp_frame(frame)
            detections = self.recognizer.detect(warped)
            state = self.recognizer.detections_to_state_dict(
                detections, warped.shape[1], warped.shape[0], self.confidence
            )
            move, score, gap = self.recognizer.infer_move_from_state(
                session.board, state, min_score=60, min_gap=4
            )
            self.last_error = None
            return [move.uci()] if move is not None else []
        except Exception as exc:
            self.last_error = str(exc)
            return []
