"""Offline local HTTP API for camera, calibration, network, and Pi state."""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, HTTPException
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

from pi_agent.calibration import CalibrationError, calibrate_from_rooks
from pi_agent.network_manager import NetworkManager
from pi_agent.setup_state import SetupReadiness
from pi_agent.uno_controller import SimulatedTransport, find_uno_port


class CalibrationRequest(BaseModel):
    corners: list[list[float]] = Field(min_length=4, max_length=4)
    board_orientation: str = "white_bottom"
    rotation_cw: int = 0


class MoveRequest(BaseModel):
    uci: str = Field(min_length=4, max_length=10)
    expected_version: int | None = None


class ModelLoadRequest(BaseModel):
    vision_mode: str | None = None
    roboflow_enabled: bool | None = None
    roboflow_model_url: str | None = None
    roboflow_api_key: str | None = None
    model_path: str | None = None
    confidence: float | None = None


def _order_corners(points):
    import numpy as np

    values = np.asarray(points, dtype="float32")
    sums = values.sum(axis=1)
    differences = np.diff(values, axis=1).reshape(-1)
    ordered = [
        values[sums.argmin()],
        values[differences.argmin()],
        values[sums.argmax()],
        values[differences.argmax()],
    ]
    return [(float(point[0]), float(point[1])) for point in ordered]


def detect_board_corners(frame):
    """Find a board-sized quadrilateral in a camera frame."""
    import cv2

    height, width = frame.shape[:2]
    minimum_area = width * height * 0.10
    maximum_area = width * height * 0.98
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)

    candidates = []
    for source in (
        cv2.Canny(gray, 30, 120),
        cv2.Canny(
            cv2.adaptiveThreshold(
                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                cv2.THRESH_BINARY, 11, 2,
            ),
            10,
            60,
        ),
    ):
        edges = cv2.dilate(source, None, iterations=2)
        contours, _ = cv2.findContours(
            edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < minimum_area or area > maximum_area:
                continue
            perimeter = cv2.arcLength(contour, True)
            quad = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
            if len(quad) == 4:
                candidates.append((area, quad.reshape(4, 2)))

    if not candidates:
        return None
    _, best = max(candidates, key=lambda candidate: candidate[0])
    return _order_corners(best)


class LocalApiHost:
    def __init__(self, game, network: NetworkManager, config: dict[str, Any], detector=None) -> None:
        self.game = game
        self.network = network
        self.detector = detector
        if self.detector is not None:
            self.detector.session_getter = lambda: self.game.session
        self.state_path = Path(config["state_path"])
        self.calibration_path = self.state_path / "camera_calibration.json"
        self._camera = None
        self._camera_lock = threading.Lock()
        self.readiness = SetupReadiness(
            vision_mode=str(config.get("vision_mode", "cloud")),
            vision_require_internet=bool(config.get("vision_require_internet", True)),
        )
        self.app = FastAPI(title="RoboChess Local Board API")
        self._routes()

    def _network(self):
        return self.network.status(
            self.config["internet_check_enabled"],
            self.config["internet_check_url"],
            self.config["internet_check_timeout"],
        ).to_dict()

    def _gantry(self) -> dict[str, Any]:
        try:
            return self.game.uno.status()
        except Exception as exc:
            return {"homed": False, "error": str(exc)}

    def _setup_status(self) -> dict[str, Any]:
        network = self._network()
        detector = self.detector.status() if self.detector else {
            "model_available": False,
            "last_error": "Camera detector is not configured",
            "camera": {"opened": False, "capture_devices": []},
        }
        return self.readiness.evaluate(
            network,
            detector,
            self.calibration_path.exists(),
            self._gantry(),
        )

    def _save_calibration(self, data: dict) -> None:
        """Persist calibration, reporting a write failure as a clean 500.

        Without this a non-writable state directory surfaced as an unhandled
        PermissionError traceback on every request.
        """
        try:
            self.state_path.mkdir(parents=True, exist_ok=True)
            self.calibration_path.write_text(json.dumps(data, indent=2))
        except OSError as exc:
            raise HTTPException(
                500,
                f"Cannot write calibration to {self.state_path}: {exc.strerror}. "
                "Set ROBOCHESS_LOCAL_STATE_PATH to a writable directory.",
            ) from exc

    def _capture(self):
        if self.detector is not None:
            try:
                return self.detector.capture_frame()
            except RuntimeError as exc:
                raise HTTPException(503, str(exc)) from exc
        try:
            import cv2
        except ImportError as exc:
            raise HTTPException(503, "OpenCV is not installed") from exc
        with self._camera_lock:
            if self._camera is None or not self._camera.isOpened():
                self._camera = cv2.VideoCapture(int(self.config["camera_index"]))
                self._camera.set(cv2.CAP_PROP_FRAME_WIDTH, int(self.config["width"]))
                self._camera.set(cv2.CAP_PROP_FRAME_HEIGHT, int(self.config["height"]))
            ok, frame = self._camera.read()
        if not ok:
            import glob

            nodes = sorted(glob.glob("/dev/video*"))
            detail = (
                "no /dev/video* devices exist - check the camera is connected"
                if not nodes
                else f"index {self.config['camera_index']} gave no frame; "
                     f"available devices: {', '.join(nodes)}"
            )
            raise HTTPException(503, f"Camera frame unavailable: {detail}")
        return frame

    def _jpeg(self, frame):
        encoded = self._encode_jpeg(frame)
        return Response(content=encoded, media_type="image/jpeg")

    def _encode_jpeg(self, frame) -> bytes:
        import cv2
        ok, encoded = cv2.imencode(
            ".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, int(self.config["jpeg_quality"])]
        )
        if not ok:
            raise HTTPException(500, "Could not encode camera frame")
        return encoded.tobytes()

    def _stream_frames(self):
        """Yield a continuous MJPEG stream for phone/tablet live preview."""
        while True:
            try:
                frame = self.detector.preview_frame() if self.detector else self._capture()
                jpeg = self._encode_jpeg(frame)
                yield (
                    b"--robochess-frame\r\n"
                    b"Content-Type: image/jpeg\r\n"
                    + f"Content-Length: {len(jpeg)}\r\n\r\n".encode()
                    + jpeg
                    + b"\r\n"
                )
                time.sleep(0.12)
            except GeneratorExit:
                return
            except Exception:
                # End the stream so Flutter can display/retry a useful error.
                return

    def _routes(self):
        @self.app.get("/local/health")
        def health():
            network = self._network()
            return {"status": "ok", "data": {
                "local_service_available": True,
                "camera_configured": True,
                "network": {**network, "backend_available": self.config.get("backend_available", False)},
            }}

        @self.app.get("/local/status")
        def status():
            network = self._network()
            vision = self.detector.status() if self.detector else {"model_available": False}
            return {"status": "ok", "data": {
                "local_service_available": True,
                "network": {**network, "backend_available": self.config.get("backend_available", False)},
                "calibrated": self.calibration_path.exists(),
                "vision": vision,
                "gantry": self._gantry(),
                "setup": self._setup_status(),
                "game": self.game.session.snapshot() if self.game.session else None,
            }}

        @self.app.get("/local/setup/status")
        def setup_status():
            setup = self._setup_status()
            return {"status": "ready" if setup["ready"] else "blocked", "data": setup}

        @self.app.get("/local/model/status")
        def model_status():
            if self.detector is None:
                return {"status": "error", "data": {
                    "model_available": False,
                    "last_error": "Camera detector is not configured",
                }}
            return {"status": "ok", "data": self.detector.status()}

        @self.app.post("/local/model/load")
        def load_model(payload: ModelLoadRequest | None = Body(default=None)):
            if self.detector is None:
                raise HTTPException(503, "Camera detector is not configured")
            if payload is not None:
                if payload.vision_mode:
                    os.environ["ROBOCHESS_VISION_MODE"] = payload.vision_mode
                if payload.roboflow_enabled is not None:
                    os.environ["ROBOCHESS_ROBOFLOW_ENABLED"] = "1" if payload.roboflow_enabled else "0"
                if payload.roboflow_model_url:
                    os.environ["ROBOCHESS_ROBOFLOW_MODEL_URL"] = payload.roboflow_model_url
                if payload.roboflow_api_key:
                    os.environ["ROBOCHESS_ROBOFLOW_API_KEY"] = payload.roboflow_api_key
                if payload.model_path:
                    os.environ["ROBOCHESS_MODEL_PATH"] = payload.model_path
                    self.detector.model_path = payload.model_path
                if payload.confidence is not None:
                    self.detector.confidence = payload.confidence
            if not os.getenv("ROBOCHESS_ROBOFLOW_MODEL_URL") and not os.getenv("ROBOFLOW_MODEL_URL"):
                os.environ["ROBOCHESS_ROBOFLOW_MODEL_URL"] = "chess-yimaf-jwsta/5"
            if not os.getenv("ROBOCHESS_ROBOFLOW_API_KEY") and not os.getenv("ROBOFLOW_API_KEY"):
                os.environ["ROBOCHESS_ROBOFLOW_API_KEY"] = "1OyUTcW3mg1dcln38uRg"
            try:
                self.detector.load_model()
            except Exception as exc:
                raise HTTPException(503, str(exc)) from exc
            data = self.detector.status()
            if not data.get("model_available"):
                raise HTTPException(
                    503, data.get("last_error") or "Vision model is not ready"
                )
            return {"status": "ok", "data": data}

        @self.app.get("/local/network/status")
        def network_status():
            return {"status": "ok", "data": {**self._network(), "backend_available": self.config.get("backend_available", False)}}

        @self.app.get("/local/camera/frame")
        def camera_frame():
            return self._jpeg(self._capture())

        @self.app.get("/local/camera/preview")
        def camera_preview():
            if self.detector is not None:
                try:
                    return self._jpeg(self.detector.preview_frame())
                except RuntimeError as exc:
                    raise HTTPException(503, str(exc)) from exc
            frame = self._capture()
            calibration = self._read_calibration()
            if calibration:
                try:
                    import cv2
                    import numpy as np
                    points = np.array(calibration["corners"], dtype="float32")
                    destination = np.array([[0, 0], [895, 0], [895, 895], [0, 895]], dtype="float32")
                    matrix = cv2.getPerspectiveTransform(points, destination)
                    frame = cv2.warpPerspective(frame, matrix, (896, 896))
                except Exception as exc:
                    raise HTTPException(422, f"Calibration preview failed: {exc}") from exc
            return self._jpeg(frame)

        @self.app.get("/local/camera/stream")
        def camera_stream():
            return StreamingResponse(
                self._stream_frames(),
                media_type="multipart/x-mixed-replace; boundary=robochess-frame",
            )

        @self.app.get("/local/calibration")
        def calibration():
            return {"status": "ok", "data": self._read_calibration()}

        @self.app.post("/local/calibration/manual")
        def manual_calibration(payload: CalibrationRequest):
            corners = payload.corners
            if len({(round(p[0], 2), round(p[1], 2)) for p in corners}) != 4:
                raise HTTPException(422, "Calibration corners must be unique")
            if payload.board_orientation not in {"white_bottom", "black_bottom"}:
                raise HTTPException(422, "Invalid board orientation")
            rotation = payload.rotation_cw
            if payload.board_orientation == "black_bottom" and rotation == 0:
                rotation = 180
            data = {
                "corners": corners,
                "board_orientation": payload.board_orientation,
                "rotation_cw": rotation,
                "method": "manual",
            }
            self._save_calibration(data)
            if self.detector is not None:
                self.detector.last_error = None
                self.detector._apply_calibration()
            return {"status": "ok", "message": "Calibration saved", "data": data}

        @self.app.post("/local/calibration/flip")
        def flip_calibration():
            data = self._read_calibration()
            if not data or "corners" not in data:
                raise HTTPException(404, "Board is not calibrated")
            curr_rot = int(data.get("rotation_cw", 0) or 0)
            new_rot = (curr_rot + 180) % 360
            data["rotation_cw"] = new_rot
            data["board_orientation"] = "black_bottom" if new_rot == 180 else "white_bottom"
            self._save_calibration(data)
            if self.detector is not None:
                self.detector._apply_calibration()
            return {"status": "ok", "message": f"Board flipped to {new_rot}°", "data": data}

        @self.app.post("/local/calibration/auto")
        def auto_calibration():
            frame = self._capture()
            data = None
            rook_note = None
            # The four corner rooks locate the board AND reveal which end is
            # white's, so they are tried before the geometry-only fallback.
            if self.detector is not None and self.detector.model_available:
                try:
                    detections = self.detector.recognizer.detect(frame)
                    data = calibrate_from_rooks(detections)
                except CalibrationError as exc:
                    rook_note = str(exc)
                except Exception as exc:  # model/runtime trouble, not a bad board
                    rook_note = f"rook calibration unavailable: {exc}"
            else:
                rook_note = "vision model not loaded; orientation not detected"

            if data is None:
                corners = detect_board_corners(frame)
                if corners is None:
                    raise HTTPException(
                        422,
                        "Could not detect a board. Place the full board in frame "
                        f"with a clear border. ({rook_note})",
                    )
                data = {
                    "corners": corners,
                    "board_orientation": "white_bottom",
                    "rotation_cw": 0,
                    "method": "contour_quad",
                }
            if rook_note:
                data["note"] = rook_note
            self._save_calibration(data)
            if self.detector is not None:
                self.detector.last_error = None
            return {"status": "ok", "message": "Calibration saved", "data": data}

        @self.app.post("/local/calibration/validate")
        def validate_calibration():
            data = self._read_calibration()
            return {"status": "ok" if data else "error", "data": data}

        @self.app.get("/local/calibration/debug")
        def calibration_debug():
            if self.detector is None or not self.detector.model_available:
                raise HTTPException(503, "Pi vision model is not ready")
            try:
                frame = self.detector.capture_frame()
                self.detector._apply_calibration()
                warped = self.detector.recognizer.warp_frame(frame)
                detections = self.detector.recognizer.detect(warped)
                by_class = {}
                for detection in detections:
                    by_class.setdefault(detection["class_name"], []).append(
                        round(float(detection["confidence"]), 3)
                    )
                return {"status": "ok", "data": {
                    "model_ref": self.detector.recognizer.model_ref,
                    "raw_detections_total": len(detections),
                    "by_class": by_class,
                    "tip": (
                        "Detections found. If validation still fails, adjust calibration corners."
                        if detections else
                        "No pieces detected. Check the camera view and Roboflow model."
                    ),
                    "vision": self.detector.status(),
                }}
            except Exception as exc:
                raise HTTPException(503, f"Pi calibration diagnostics failed: {exc}") from exc

        @self.app.post("/local/calibration/force")
        def force_validate():
            if self.detector is None or not self.detector.model_available:
                raise HTTPException(503, "Pi vision model is not ready")
            return {"status": "ok", "data": {
                "valid": True,
                "warning": "Position was not verified by the camera.",
                "vision": self.detector.status(),
            }}

        @self.app.post("/local/calibration/validate-start")
        def validate_start():
            if self.detector is None or not self.detector.model_available:
                raise HTTPException(503, "Pi vision model is not ready")
            if not self.detector.calibrated:
                raise HTTPException(409, "Board is not calibrated")
            try:
                frame = self.detector.capture_frame()
                self.detector._apply_calibration()
                state = self.detector.recognizer.detections_to_state_dict(
                    self.detector.recognizer.detect(
                        self.detector.recognizer.warp_frame(frame)
                    ),
                    self.detector.recognizer.BOARD_SIZE,
                    self.detector.recognizer.BOARD_SIZE,
                    self.detector.confidence,
                )
                expected = self.detector.recognizer.expected_initial_state()
                missing = sum(1 for sq, value in expected.items() if value and not state.get(sq))
                extra = sum(1 for sq, value in state.items() if value and not expected.get(sq))
                wrong_color = sum(
                    1 for sq, value in state.items()
                    if value and expected.get(sq) and value.split("_", 1)[0] != expected[sq].split("_", 1)[0]
                )
                valid = missing <= 16 and extra <= 6 and wrong_color == 0
                self.readiness.mark_starting_position(valid)
                return {"status": "ok", "data": {
                    "valid": valid,
                    "pieces_detected": sum(1 for value in state.values() if value),
                    "summary": {
                        "missing": missing,
                        "extra": extra,
                        "wrong_color": wrong_color,
                    },
                    "vision": self.detector.status(),
                    "setup": self._setup_status(),
                }}
            except Exception as exc:
                raise HTTPException(503, f"Pi board validation failed: {exc}") from exc

        @self.app.post("/local/game/start")
        def start_game():
            setup = self._setup_status()
            result = self.game.handle({"type": "session.start", "data": {}})
            if self.detector is not None:
                self.detector.pending_auto_move = None
                self.detector.pending_auto_san = None
                self.detector.start_hand_monitoring(self.game.session)
            return {"status": "ok", "data": {**result, "setup": setup}}

        @self.app.post("/local/game/reset")
        def reset_game():
            if self.detector is not None:
                self.detector.pending_auto_move = None
                self.detector.pending_auto_san = None
            return {"status": "ok", "data": self.game.handle({"type": "session.reset", "data": {}})}

        @self.app.post("/local/game/move")
        def game_move(payload: MoveRequest):
            if self.detector is not None:
                self.detector.pending_auto_move = None
                self.detector.pending_auto_san = None
            return {"status": "ok", "data": self.game.handle({
                "type": "move.propose",
                "data": {"uci": payload.uci, "expected_version": payload.expected_version},
            })}

        @self.app.post("/local/game/undo")
        def undo_game():
            if self.detector is not None:
                self.detector.pending_auto_move = None
                self.detector.pending_auto_san = None
            return {"status": "ok", "data": self.game.handle({"type": "session.undo", "data": {}})}

        @self.app.get("/local/move/auto-detect-ready")
        def auto_detect_ready():
            setup = self._setup_status()
            hand_present = bool(self.detector and self.detector.hand_present)
            session = self.game.session
            phase = getattr(getattr(session, "phase", None), "value", None)
            snapshot = session.snapshot() if session else None
            if session and phase != "player_turn":
                return {"status": "ok", "data": {
                    "ready": False,
                    "reason": "engine_move" if phase in {
                        "awaiting_engine", "executing_engine_move"
                    } else phase or "no_session",
                    "hand_present": hand_present,
                    "state": snapshot,
                }}
            pending_move = self.detector.pending_auto_move if self.detector else None
            pending_san = self.detector.pending_auto_san if self.detector else None

            # If no pending move yet and hand is not on board, do a quick opportunistic check
            if pending_move is None and not hand_present and self.detector and self.detector.model_available and self.detector.calibrated and session:
                try:
                    candidates = self.detector.detect_candidates(session)
                    if candidates:
                        pending_move = candidates[0]
                        try:
                            import chess
                            pending_san = session.board.san(chess.Move.from_uci(pending_move))
                        except Exception:
                            pending_san = pending_move
                except Exception:
                    pass

            if pending_move is not None and self.game.session:
                if self.detector:
                    with self.detector._lock:
                        self.detector.pending_auto_move = None
                        self.detector.pending_auto_san = None

                # Propose human move to game session
                result = self.game.handle({
                    "type": "move.propose",
                    "data": {"uci": pending_move, "expected_version": self.game.session.version},
                })
                current_snapshot = self.game.session.snapshot() if self.game.session else None
                return {"status": "ok", "data": {
                    "ready": True,
                    "uci": pending_move,
                    "san": pending_san or pending_move,
                    "fen": self.game.session.board.fen() if self.game.session else None,
                    "reason": "move_detected",
                    "hand_present": False,
                    "engine_pending": bool(result.get("engine_pending")),
                    "state": current_snapshot,
                    **result,
                }}

            if not self.detector or not self.detector.model_available:
                reason = "vision_model_not_ready"
            elif not self.detector.calibrated:
                reason = "board_not_calibrated"
            elif hand_present:
                reason = "hand_present"
            else:
                reason = "waiting_for_move"

            return {"status": "ok", "data": {
                "ready": False,
                "reason": reason,
                "hand_present": hand_present,
                "missing": setup["missing"],
                "vision": self.detector.status() if self.detector else {},
                "state": snapshot,
            }}

        @self.app.post("/local/move/detect-if-clear")
        def detect_move_if_clear():
            if self.detector:
                self.detector.hand_present = False
            return self._detect_result()

        @self.app.post("/local/move/analyze")
        def analyze_move():
            if self.detector:
                self.detector.hand_present = False
            return self._detect_result()

        @self.app.post("/local/move/analyze-and-reply")
        def analyze_and_reply():
            # Manual snapshot detection requested by user.
            # Never block on hand_present! Clear it and detect current frame.
            if self.detector is not None:
                self.detector.hand_present = False
            return self._detect_result(apply_move=True)

        @self.post_gantry("/local/gantry/home")
        def gantry_home():
            # If currently simulated, check if physical Uno is available and auto-reconnect
            if isinstance(self.game.uno.transport, SimulatedTransport):
                port = find_uno_port()
                if port:
                    try:
                        self.game.uno.reconnect(port)
                    except Exception:
                        pass
            result = self.game.handle({"type": "gantry.home", "data": {}})
            is_sim = isinstance(self.game.uno.transport, SimulatedTransport)
            port_used = getattr(self.game.uno.transport, "port", None)
            return {
                "status": "ok",
                "data": {
                    **result,
                    "simulated": is_sim,
                    "port": port_used,
                    "setup": self._setup_status(),
                },
            }

        @self.post_gantry("/local/gantry/reconnect")
        def gantry_reconnect():
            result = self.game.uno.reconnect()
            return {"status": "ok", "data": result}

        @self.app.get("/local/gantry/status")
        def gantry_status():
            return {"status": "ok", "data": self.game.handle({"type": "gantry.status", "data": {}})}

        @self.post_gantry("/local/gantry/stop")
        def gantry_stop():
            try:
                self.game.uno.stop()
            except AttributeError as exc:
                raise HTTPException(500, "Gantry controller does not expose STOP") from exc
            except Exception as exc:
                raise HTTPException(503, f"Gantry stop failed: {exc}") from exc
            return {"status": "ok", "data": {"status": "stopped"}}

        @self.app.post("/local/move/detect")
        def detect_move():
            return self._detect_result()

        @self.app.get("/local/game/state")
        def game_state():
            return {"status": "ok", "data": self.game.session.snapshot() if self.game.session else None}

        @self.app.get("/local/game/session")
        def game_session():
            session = self.game.session
            if session is None:
                return {"status": "ok", "data": None}
            return {"status": "ok", "data": session.snapshot()}

    def post_gantry(self, path: str):
        return self.app.post(path)

    def _detect_result(self, apply_move: bool = False):
        if self.detector is None:
            raise HTTPException(503, "Camera detector is not configured")
        if not self.game.session:
            raise HTTPException(409, "Start a local game session first")
        if not self.detector.model_available:
            err = self.detector.last_error or "Vision model is not loaded or configured"
            return {
                "status": "error",
                "data": {
                    "analysis_status": "error",
                    "reason": "vision_model_not_ready",
                    "analysis_message": f"Vision model not ready: {err}. You can tap your move on screen.",
                    "retry": False,
                    "vision": self.detector.status(),
                },
            }
        if not self.detector.calibrated:
            return {
                "status": "error",
                "data": {
                    "analysis_status": "error",
                    "reason": "board_not_calibrated",
                    "analysis_message": "Board is not calibrated. Calibrate the board first, or tap your move on screen.",
                    "retry": False,
                    "vision": self.detector.status(),
                },
            }
        candidates = self.detector.detect_candidates(self.game.session)
        if not candidates:
            if self.detector.last_error:
                msg = f"Vision error: {self.detector.last_error}. You can also tap your move on screen."
                reason = "vision_error"
            else:
                msg = "No move detected yet. Try moving a piece and removing your hand, or tap your move on screen."
                reason = "no_legal_move"
            return {
                "status": "waiting",
                "data": {
                    "analysis_status": "waiting",
                    "reason": reason,
                    "analysis_message": msg,
                    "retry": False,
                    "vision": self.detector.status(),
                },
            }
        move_uci = candidates[0]
        if not apply_move:
            return {"status": "move_detected", "data": {"candidates": candidates, "vision": self.detector.status()}}
        result = self.game.handle({"type": "move.propose", "data": {"uci": move_uci, "expected_version": self.game.session.version}})
        return {
            "status": "ok",
            "data": {
                "human_move": {"uci": move_uci, "analysis_status": "success"},
                "engine_move": None,
                "engine_pending": bool(result.get("engine_pending")),
                "fen": self.game.session.board.fen() if self.game.session else None,
                **result,
            },
        }

    def _read_calibration(self) -> dict:
        try:
            return json.loads(self.calibration_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}


def start_local_api(host: str, port: int, game, network: NetworkManager, config: dict, detector=None) -> threading.Thread:
    import uvicorn
    api = LocalApiHost(game, network, config, detector)
    thread = threading.Thread(
        target=uvicorn.run,
        kwargs={"app": api.app, "host": host, "port": port, "log_level": "warning"},
        daemon=True,
        name="robochess-local-api",
    )
    thread.start()
    return thread
