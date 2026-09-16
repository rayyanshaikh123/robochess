"""Shared Pi camera capture and local board-state move detection."""

from __future__ import annotations

import glob
import json
import os
import threading
from pathlib import Path
from typing import Any

from pi_agent.calibration import rotate_warped
from pi_agent.vision_recognizer import BoardRecognizer


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
        self.hand_present: bool = False
        self.hand_last_seen: float = 0.0
        self.last_trigger_time: float = 0.0
        self.pending_auto_move: str | None = None
        self.pending_auto_san: str | None = None
        self.active_session: Any = None
        self.session_getter: Any = None
        self._hand_stop_event = threading.Event()
        self._hand_thread: threading.Thread | None = None
        self._load_recognizer()

    def _load_recognizer(self) -> None:
        try:
            from pi_agent.config import load_local_env
            load_local_env()
        except Exception:
            pass
        cloud_enabled = (
            os.getenv("ROBOCHESS_VISION_MODE", "auto").strip().lower() in {"cloud", "auto"}
            or os.getenv("ROBOCHESS_ROBOFLOW_ENABLED", "1").strip().lower()
            in {"1", "true", "yes", "on"}
        )
        cloud_url = (
            os.getenv("ROBOCHESS_ROBOFLOW_MODEL_URL", "").strip()
            or os.getenv("ROBOFLOW_MODEL_URL", "").strip()
            or "chess-yimaf-jwsta/5"
        )
        cloud_key = (
            os.getenv("ROBOCHESS_ROBOFLOW_API_KEY", "").strip()
            or os.getenv("ROBOFLOW_API_KEY", "").strip()
            or "1OyUTcW3mg1dcln38uRg"
        )

        # If a local model path was given but does not exist on disk, fallback to cloud if key exists
        local_exists = bool(self.model_path and Path(self.model_path).is_file())
        if not local_exists and cloud_key:
            cloud_enabled = True
            os.environ["ROBOCHESS_VISION_MODE"] = "cloud"
            os.environ["ROBOCHESS_ROBOFLOW_ENABLED"] = "1"

        if not local_exists and not (cloud_enabled and cloud_key):
            # Check standard fallback locations before giving up
            for candidate in [
                Path("/var/lib/robochess/models/best.pt"),
                Path("/opt/robochess/models/best.pt"),
                Path(__file__).resolve().parent / "models" / "best.pt",
                Path.cwd() / "models" / "best.pt",
            ]:
                if candidate.is_file():
                    self.model_path = str(candidate)
                    local_exists = True
                    break

        if not local_exists and not (cloud_enabled and cloud_key):
            self.last_error = (
                f"No local model found at '{self.model_path or 'not specified'}' "
                "and Roboflow API key is not configured."
            )
            return

        try:
            effective_model = self.model_path if local_exists else "cloud"
            self.recognizer = BoardRecognizer(effective_model, self.confidence)
            if not self.recognizer.is_ready:
                self.last_error = getattr(self.recognizer, "last_error", None) or "Vision model could not be initialized"
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
        if self.recognizer is None or not getattr(self.recognizer, "is_ready", False):
            try:
                self._load_recognizer()
            except Exception:
                pass
        return bool(self.recognizer and getattr(self.recognizer, "is_ready", False))

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
        calibration = self._read_calibration()
        corners = calibration.get("corners")
        if corners and len(corners) == 4:
            self.recognizer.calibrate([(float(p[0]), float(p[1])) for p in corners])
            
        orientation = calibration.get("board_orientation", "white_bottom")
        rotation_cw = self._rotation_cw()
        # _warp applies rotation_cw. Only set is_flipped if unrotated and black_bottom.
        self.recognizer.is_flipped = (orientation == "black_bottom" and rotation_cw == 0)

    def _video_nodes(self) -> list[str]:
        return sorted(glob.glob("/dev/video*"),
                      key=lambda path: self._node_index(path) or 0)

    @staticmethod
    def _node_index(path: str) -> int | None:
        try:
            return int(path.replace("/dev/video", ""))
        except ValueError:
            return None

    @staticmethod
    def _node_name(path: str) -> str:
        """Driver-reported name, e.g. 'bcm2835-isp' or 'HD Webcam C270'."""
        index = PiCameraDetector._node_index(path)
        if index is None:
            return ""
        try:
            with open(f"/sys/class/video4linux/video{index}/name") as handle:
                return handle.read().strip()
        except OSError:
            return ""

    @staticmethod
    def _is_capture_device(path: str) -> bool | None:
        """Whether a node can actually capture video.

        A Pi publishes many /dev/video* nodes that are ISP or codec endpoints
        rather than cameras. Opening one never yields a frame and can block for
        ~10s inside select(), so they must be excluded before probing. Returns
        None when the capability cannot be determined (non-Linux, or the ioctl
        is unsupported), so the caller can fall back to trying everything.
        """
        try:
            import fcntl
            import struct
        except ImportError:
            return None

        # VIDIOC_QUERYCAP = _IOR('V', 0, struct v4l2_capability), 104 bytes.
        VIDIOC_QUERYCAP = 0x80685600
        V4L2_CAP_VIDEO_CAPTURE = 0x00000001
        try:
            with open(path, "rb", buffering=0) as handle:
                buf = bytearray(104)
                fcntl.ioctl(handle.fileno(), VIDIOC_QUERYCAP, buf)
                caps = struct.unpack_from("<I", buf, 16)[0]
                return bool(caps & V4L2_CAP_VIDEO_CAPTURE)
        except OSError:
            return False

    def _capture_nodes(self) -> list[str]:
        """Video nodes that report capture capability."""
        nodes = self._video_nodes()
        checked = [(node, self._is_capture_device(node)) for node in nodes]
        if all(result is None for _, result in checked):
            # Capability probing unavailable; fall back to trying everything.
            return nodes
        return [node for node, result in checked if result]

    def _candidate_indices(self) -> list[int]:
        """Capture-capable indices, the configured one first if it qualifies."""
        indices = [index for index in
                   (self._node_index(node) for node in self._capture_nodes())
                   if index is not None]
        if self.camera_index in indices:
            indices.remove(self.camera_index)
            indices.insert(0, self.camera_index)
        return indices

    def _diagnose(self) -> str:
        """Explain why no camera could be opened, in terms the user can act on."""
        nodes = self._video_nodes()
        if not nodes:
            return ("no /dev/video* devices exist - check the camera is plugged "
                    "in and, for a Pi Camera Module, that it is enabled")

        capture = self._capture_nodes()
        if not capture:
            names = sorted({self._node_name(node) for node in nodes} - {""})
            described = f" (they are {', '.join(names)} nodes)" if names else ""
            return (f"{len(nodes)} video devices exist but none can capture"
                    f"{described} - no camera is connected. Re-seat the USB "
                    "camera, or for a CSI camera module check `rpicam-hello`")

        unreadable = [node for node in capture if not os.access(node, os.R_OK)]
        if unreadable:
            return (f"no permission to read {', '.join(unreadable)} - add the "
                    "service user to the 'video' group and restart")
        return (f"{', '.join(capture)} can capture but returned no frame - "
                "another process may still hold the camera")

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
            return self._warp(frame)
        return frame

    def status(self) -> dict:
        recognizer_status = self.recognizer.status() if self.recognizer else {}
        return {
            "configured": True,
            "calibrated": self.calibrated,
            "ready": self.model_available,
            "hand_present": self.hand_present,
            "pending_auto_move": self.pending_auto_move,
            "camera_index": self.camera_index,
            "last_error": self.last_error,
            "detector": recognizer_status,
            # Surfaced so a camera problem can be diagnosed from the app
            # instead of only from the Pi's console.
            "camera": {
                "index": self.camera_index,
                "opened": bool(self._camera is not None and self._camera.isOpened()),
                "devices": self._video_nodes(),
                "capture_devices": self._capture_nodes(),
                "device_names": {
                    node: self._node_name(node) for node in self._video_nodes()
                },
            },
        }

    def detect_candidates(self, session) -> list[str]:
        if not session or getattr(session.phase, "value", session.phase) != "player_turn":
            return []
        if not self.model_available:
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
                session.board, state, min_score=40, min_gap=1
            )
            if move is None:
                # Fallback to occupancy matching
                occupancy = self.recognizer.to_occupancy_state(state)
                move, score, gap = self.recognizer.infer_move_from_occupancy(
                    session.board, occupancy, min_score=38, min_gap=1
                )
            self.last_error = None
            return [move.uci()] if move is not None else []
        except Exception as exc:
            self.last_error = str(exc)
            return []

    def start_hand_monitoring(self, session=None) -> None:
        """Start background hand motion monitoring loop."""
        if session is not None:
            self.active_session = session
        if self._hand_thread is not None and self._hand_thread.is_alive():
            return
        self._hand_stop_event.clear()
        self._hand_thread = threading.Thread(
            target=self._hand_loop, daemon=True, name="pi-hand-monitor"
        )
        self._hand_thread.start()

    def stop_hand_monitoring(self) -> None:
        """Stop background hand motion monitoring loop."""
        self._hand_stop_event.set()
        if self._hand_thread is not None and self._hand_thread.is_alive():
            self._hand_thread.join(timeout=1.0)
        self._hand_thread = None

    def _hand_loop(self) -> None:
        """Continuously check for hand motion and trigger detection on hand departure.
        Also evaluates steady board state so moves are detected even if the initial
        departure snapshot was missed or hand was moved quickly.
        """
        import time
        try:
            import cv2
            import numpy as np
        except ImportError:
            return

        MOTION_DIFF_THRESHOLD = 28
        MOTION_BLUR = 7
        MOTION_RATIO_TRIGGER = 0.04
        HAND_ABSENCE_SECONDS = 0.4
        HAND_TRIGGER_COOLDOWN = 0.6
        STEADY_EVAL_INTERVAL = 1.2

        prev_gray = None
        kernel = np.ones((5, 5), np.uint8)
        steady_start_time = None
        last_steady_eval_time = 0.0

        while not self._hand_stop_event.is_set():
            session = (self.session_getter() if self.session_getter else None) or self.active_session
            session_is_over = bool(getattr(session, "is_over", False)) if session else True
            session_phase = getattr(getattr(session, "phase", None), "value", None)
            if session is None or session_is_over or session_phase != "player_turn":
                self.hand_present = False
                steady_start_time = None
                time.sleep(0.15)
                continue
            if not self.calibrated or not self.model_available:
                time.sleep(0.2)
                continue

            if self.pending_auto_move is not None:
                # Move is already pending for local API pickup
                time.sleep(0.1)
                continue

            try:
                frame = self.capture_frame()
            except Exception:
                time.sleep(0.2)
                continue

            if frame is None:
                time.sleep(0.1)
                continue

            cal = self._read_calibration()
            corners = cal.get("corners")
            roi = frame
            if corners and len(corners) == 4:
                xs = [int(p[0]) for p in corners]
                ys = [int(p[1]) for p in corners]
                x1 = max(0, min(xs))
                x2 = min(frame.shape[1], max(xs))
                y1 = max(0, min(ys))
                y2 = min(frame.shape[0], max(ys))
                if x2 - x1 > 10 and y2 - y1 > 10:
                    roi = frame[y1:y2, x1:x2]

            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            if MOTION_BLUR > 0:
                gray = cv2.GaussianBlur(gray, (MOTION_BLUR, MOTION_BLUR), 0)

            if prev_gray is None or prev_gray.shape != gray.shape:
                prev_gray = gray
                time.sleep(0.1)
                continue

            diff = cv2.absdiff(prev_gray, gray)
            _, thresh = cv2.threshold(diff, MOTION_DIFF_THRESHOLD, 255, cv2.THRESH_BINARY)
            # Filter isolated camera sensor noise
            opened = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel)
            motion_ratio = float(np.count_nonzero(opened)) / float(opened.size)
            prev_gray = gray
            now = time.time()

            if motion_ratio >= MOTION_RATIO_TRIGGER:
                self.hand_present = True
                self.hand_last_seen = now
                steady_start_time = None
            else:
                if steady_start_time is None:
                    steady_start_time = now

                if self.hand_present and (now - self.hand_last_seen) >= HAND_ABSENCE_SECONDS:
                    self.hand_present = False
                    if (now - self.last_trigger_time) >= HAND_TRIGGER_COOLDOWN:
                        self.last_trigger_time = now
                        self._on_hand_left(session)
                        last_steady_eval_time = time.time()
                elif not self.hand_present and self.pending_auto_move is None:
                    # Continuous evaluation on steady board:
                    # If the board is motionless for >= 0.5s and not recently evaluated, check for a legal move
                    if (now - steady_start_time) >= 0.5 and (now - last_steady_eval_time) >= STEADY_EVAL_INTERVAL:
                        last_steady_eval_time = now
                        self._evaluate_steady_board(session)

            time.sleep(0.1)

    def _evaluate_steady_board(self, session) -> None:
        """Opportunistically evaluate the stationary board for legal moves."""
        if not session or getattr(session.phase, "value", session.phase) != "player_turn":
            return
        if self.pending_auto_move is not None:
            return
        candidates = self.detect_candidates(session)
        if candidates:
            move_uci = candidates[0]
            san = move_uci
            try:
                import chess
                m = chess.Move.from_uci(move_uci)
                san = session.board.san(m)
            except Exception:
                pass
            with self._lock:
                self.pending_auto_move = move_uci
                self.pending_auto_san = san

    def _on_hand_left(self, session=None) -> None:
        """Triggered when the hand departs after making a move."""
        import time
        if session is None:
            session = (self.session_getter() if self.session_getter else None) or self.active_session
        session_is_over = bool(getattr(session, "is_over", False)) if session else True
        session_phase = getattr(getattr(session, "phase", None), "value", None)
        if session is None or session_is_over or session_phase != "player_turn":
            return
        # Brief pause to let camera exposure stabilize after hand leaves
        time.sleep(0.15)
        self._evaluate_steady_board(session)
