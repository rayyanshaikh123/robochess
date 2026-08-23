"""Shared Pi camera capture and local board-state move detection."""

from __future__ import annotations

import glob
import json
import os
import threading
from pathlib import Path
from typing import Any

from pi_agent.calibration import rotate_warped


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
        cloud_enabled = (
            os.getenv("ROBOCHESS_VISION_MODE", "").strip().lower() == "cloud"
            or os.getenv("ROBOCHESS_ROBOFLOW_ENABLED", "0").strip().lower()
            in {"1", "true", "yes", "on"}
            or (
                (
                    os.getenv("ROBOCHESS_ROBOFLOW_API_KEY", "").strip()
                    or os.getenv("ROBOFLOW_API_KEY", "").strip()
                )
                and (
                    os.getenv("ROBOCHESS_ROBOFLOW_MODEL_URL", "").strip()
                    or os.getenv("ROBOFLOW_MODEL_URL", "").strip()
                    or "/" in self.model_path
                )
            )
        )
        cloud_url = os.getenv("ROBOCHESS_ROBOFLOW_MODEL_URL", "").strip() or os.getenv(
            "ROBOFLOW_MODEL_URL", ""
        ).strip()
        cloud_key = os.getenv("ROBOCHESS_ROBOFLOW_API_KEY", "").strip() or os.getenv(
            "ROBOFLOW_API_KEY", ""
        ).strip()
        if not self.model_path and not (cloud_enabled and cloud_key):
            self.last_error = "Configure a local model path or Roboflow model/key"
            return
        try:
            from backend.board_recognizer import BoardRecognizer
            self.recognizer = BoardRecognizer(self.model_path, self.confidence)
            if not self.recognizer.is_ready:
                self.last_error = "Vision model could not be loaded"
            else:
                self.last_error = None
        except Exception as exc:
            self.last_error = str(exc)

    def load_model(self) -> None:
        with self._lock:
            self.recognizer = None
            self.last_error = None
            self._load_recognizer()

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

    def _video_nodes(self) -> list[str]:
        return sorted(glob.glob("/dev/video*"))

    def _candidate_indices(self) -> list[int]:
        """Indices worth trying, configured one first.

        On a Pi the configured index is often wrong: the bcm2835 codec occupies
        the low /dev/video* nodes, so a USB webcam commonly lands on video1 or
        higher. Probing the rest means a wrong index self-corrects instead of
        failing forever.
        """
        candidates = [self.camera_index]
        for node in self._video_nodes():
            try:
                index = int(node.replace("/dev/video", ""))
            except ValueError:
                continue
            if index not in candidates:
                candidates.append(index)
        return candidates

    def _diagnose(self) -> str:
        """Explain why no camera could be opened, in terms the user can act on."""
        nodes = self._video_nodes()
        if not nodes:
            return ("no /dev/video* devices exist - check the camera is plugged "
                    "in and, for a Pi Camera Module, that it is enabled")
        unreadable = [node for node in nodes if not os.access(node, os.R_OK)]
        if unreadable:
            return (f"no permission to read {', '.join(unreadable)} - add the "
                    "service user to the 'video' group and restart")
        return (f"{', '.join(nodes)} exist but none returned a frame - another "
                "process may still hold the camera")

    def _release(self) -> None:
        if self._camera is not None:
            try:
                self._camera.release()
            except Exception:
                pass
            self._camera = None

    def _try_open(self, cv2, index: int, backend: int, size: tuple[int, int]):
        """Open one index/backend/size combination, or None if it yields nothing."""
        camera = cv2.VideoCapture(index, backend)
        if not camera.isOpened():
            camera.release()
            return None
        # The C270 exposes V4L2 MJPEG/YUYV modes; selecting MJPEG explicitly
        # avoids unsupported-resolution negotiation failures.
        camera.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, size[0])
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, size[1])
        ok, frame = camera.read()
        if not ok or frame is None:
            camera.release()
            return None
        return camera, frame

    def _open_any(self, cv2):
        """Find a working camera, trying V4L2 first then any other backend."""
        backends = [getattr(cv2, "CAP_V4L2", 0), getattr(cv2, "CAP_ANY", 0)]
        sizes = [(self.width, self.height), (800, 600), (640, 480)]
        for index in self._candidate_indices():
            for backend in backends:
                for size in sizes:
                    opened = self._try_open(cv2, index, backend, size)
                    if opened is None:
                        continue
                    camera, frame = opened
                    # Remember what worked so later frames skip the probing.
                    self.camera_index = index
                    self.last_error = None
                    return camera, frame
        return None

    def capture_frame(self):
        try:
            import cv2
        except ImportError as exc:
            raise RuntimeError("OpenCV is not installed") from exc

        with self._lock:
            if self._camera is not None and self._camera.isOpened():
                ok, frame = self._camera.read()
                if ok and frame is not None:
                    return frame
                # The device went away mid-session; drop it and re-probe.
                self._release()

            opened = self._open_any(cv2)
            if opened is None:
                reason = self._diagnose()
                self.last_error = f"Camera unavailable: {reason}"
                raise RuntimeError(self.last_error)
            self._camera, frame = opened
            return frame

    def _rotation_cw(self) -> int:
        """Post-warp rotation that brings rank 1 to the bottom of the image."""
        try:
            return int(self._read_calibration().get("rotation_cw", 0) or 0)
        except (TypeError, ValueError):
            return 0

    def _warp(self, frame):
        """Top-down board view, oriented so rank 1 is at the bottom.

        The recognizer's own warp always lands the image's top-left corner at
        the warped origin, so board orientation has to be corrected here rather
        than by reordering the calibration corners.
        """
        return rotate_warped(self.recognizer.warp_frame(frame), self._rotation_cw())

    def preview_frame(self):
        frame = self.capture_frame()
        if self.recognizer:
            self._apply_calibration()
            return self._warp(frame) if self.calibrated else frame
        return frame

    def status(self) -> dict:
        recognizer_status = self.recognizer.status() if self.recognizer else {}
        return {
            "model_available": self.model_available,
            "calibrated": self.calibrated,
            "model_path_configured": bool(self.model_path),
            "last_error": self.last_error,
            "detector": recognizer_status,
            # Surfaced so a camera problem can be diagnosed from the app
            # instead of only from the Pi's console.
            "camera": {
                "index": self.camera_index,
                "opened": bool(self._camera is not None and self._camera.isOpened()),
                "devices": self._video_nodes(),
            },
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
            warped = self._warp(frame)
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
