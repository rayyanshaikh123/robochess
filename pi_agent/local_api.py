"""Offline local HTTP API for camera, calibration, network, and Pi state."""

from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

from pi_agent.network_manager import NetworkManager


class CalibrationRequest(BaseModel):
    corners: list[list[float]] = Field(min_length=4, max_length=4)
    board_orientation: str = "white_bottom"


class MoveRequest(BaseModel):
    uci: str = Field(min_length=4, max_length=10)
    expected_version: int | None = None


class LocalApiHost:
    def __init__(self, game, network: NetworkManager, config: dict[str, Any], detector=None) -> None:
        self.game = game
        self.network = network
        self.config = config
        self.detector = detector
        self.state_path = Path(config["state_path"])
        self.calibration_path = self.state_path / "camera_calibration.json"
        self._camera = None
        self._camera_lock = threading.Lock()
        self.app = FastAPI(title="RoboChess Local Board API")
        self._routes()

    def _network(self):
        return self.network.status(
            self.config["internet_check_enabled"],
            self.config["internet_check_url"],
            self.config["internet_check_timeout"],
        ).to_dict()

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
            raise HTTPException(503, "Camera frame unavailable")
        return frame

    def _jpeg(self, frame):
        import cv2
        ok, encoded = cv2.imencode(
            ".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, int(self.config["jpeg_quality"])]
        )
        if not ok:
            raise HTTPException(500, "Could not encode camera frame")
        return Response(content=encoded.tobytes(), media_type="image/jpeg")

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
            return {"status": "ok", "data": {
                "local_service_available": True,
                "network": {**network, "backend_available": self.config.get("backend_available", False)},
                "calibrated": self.calibration_path.exists(),
                "vision": self.detector.status() if self.detector else {"model_available": False},
                "game": self.game.session.snapshot() if self.game.session else None,
            }}

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
            self.state_path.mkdir(parents=True, exist_ok=True)
            data = {"corners": corners, "board_orientation": payload.board_orientation}
            self.calibration_path.write_text(json.dumps(data, indent=2))
            if self.detector is not None:
                self.detector.last_error = None
            return {"status": "ok", "message": "Calibration saved", "data": data}

        @self.app.post("/local/calibration/auto")
        def auto_calibration():
            raise HTTPException(501, "Automatic local calibration requires board-corner detection")

        @self.app.post("/local/calibration/validate")
        def validate_calibration():
            data = self._read_calibration()
            return {"status": "ok" if data else "error", "data": data}

        @self.app.post("/local/game/start")
        def start_game():
            return {"status": "ok", "data": self.game.handle({"type": "session.start", "data": {}})}

        @self.app.post("/local/game/reset")
        def reset_game():
            return {"status": "ok", "data": self.game.handle({"type": "session.reset", "data": {}})}

        @self.app.post("/local/game/move")
        def game_move(payload: MoveRequest):
            return {"status": "ok", "data": self.game.handle({
                "type": "move.propose",
                "data": {"uci": payload.uci, "expected_version": payload.expected_version},
            })}

        @self.app.post("/local/game/undo")
        def undo_game():
            raise HTTPException(501, "Undo is not implemented in the Pi session controller")

        @self.app.post("/local/move/detect-if-clear")
        def detect_move_if_clear():
            return self._detect_result()

        @self.app.post("/local/move/analyze")
        def analyze_move():
            return self._detect_result()

        @self.app.post("/local/move/analyze-and-reply")
        def analyze_and_reply():
            return self._detect_result(apply_move=True)

        @self.post_gantry("/local/gantry/home")
        def gantry_home():
            return {"status": "ok", "data": self.game.handle({"type": "gantry.home", "data": {}})}

        @self.app.get("/local/gantry/status")
        def gantry_status():
            return {"status": "ok", "data": self.game.handle({"type": "gantry.status", "data": {}})}

        @self.post_gantry("/local/gantry/stop")
        def gantry_stop():
            try:
                self.game.uno.stop()
            except AttributeError:
                raise HTTPException(501, "Gantry stop is not supported by the current controller")
            return {"status": "ok", "data": {"status": "stopped"}}

        @self.app.post("/local/move/detect")
        def detect_move():
            return self._detect_result()

        @self.app.get("/local/game/state")
        def game_state():
            return {"status": "ok", "data": self.game.session.snapshot() if self.game.session else None}

    def post_gantry(self, path: str):
        return self.app.post(path)

    def _detect_result(self, apply_move: bool = False):
        if self.detector is None:
            raise HTTPException(503, "Camera detector is not configured")
        if not self.game.session:
            raise HTTPException(409, "Start a local game session first")
        candidates = self.detector.detect_candidates(self.game.session)
        if not candidates:
            return {"status": "no_move", "data": {"vision": self.detector.status()}}
        if not apply_move:
            return {"status": "move_detected", "data": {"candidates": candidates, "vision": self.detector.status()}}
        result = self.game.handle({"type": "move.propose", "data": {"uci": candidates[0], "expected_version": self.game.session.version}})
        return {"status": "ok", "data": result}

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
