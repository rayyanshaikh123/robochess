"""
Board Recognizer — Convert YOLO detections to chess board state.

This module handles:
  1. Loading the YOLO model
  2. Running inference on a frame/image
  3. Mapping detected piece bounding boxes to board squares
  4. Building a chess.Board from detections
  5. Inferring moves by comparing consecutive board states
"""

import cv2
import numpy as np
import chess
import os
import requests
import time
from urllib.parse import urlparse
from pathlib import Path
from typing import Optional

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None

# Class ID → (chess.PieceType, chess.Color)
CLASS_MAP = {
    0:  (chess.BISHOP, chess.BLACK), # black_bishop
    1:  (chess.KING,   chess.BLACK), # black_king
    2:  (chess.KNIGHT, chess.BLACK), # black_knight
    3:  (chess.PAWN,   chess.BLACK), # black_pawn
    4:  (chess.QUEEN,  chess.BLACK), # black_queen
    5:  (chess.ROOK,   chess.BLACK), # black_rook
    6:  (chess.BISHOP, chess.WHITE), # white_bishop
    7:  (chess.KING,   chess.WHITE), # white_king
    8:  (chess.KNIGHT, chess.WHITE), # white_knight
    9:  (chess.PAWN,   chess.WHITE), # white_pawn
    10: (chess.QUEEN,  chess.WHITE), # white_queen
    11: (chess.ROOK,   chess.WHITE), # white_rook
}

CLASS_NAMES = [
    "black_bishop", "black_king", "black_knight", "black_pawn",
    "black_queen", "black_rook", "white_bishop", "white_king",
    "white_knight", "white_pawn", "white_queen", "white_rook",
]

DISPLAY_COLORS = {
    "white_queen": (255, 214, 102),
    "white_king": (102, 220, 255),
    "white_rook": (120, 255, 160),
    "white_bishop": (255, 168, 120),
    "white_knight": (210, 160, 255),
    "white_pawn": (255, 245, 180),
    "black_queen": (80, 180, 255),
    "black_king": (255, 120, 180),
    "black_rook": (120, 160, 255),
    "black_bishop": (255, 140, 90),
    "black_knight": (140, 255, 220),
    "black_pawn": (200, 200, 200),
}

DISPLAY_CODES = {
    "white_queen": "WQ",
    "white_king": "WK",
    "white_rook": "WR",
    "white_bishop": "WB",
    "white_knight": "WN",
    "white_pawn": "WP",
    "black_queen": "BQ",
    "black_king": "BK",
    "black_rook": "BR",
    "black_bishop": "BB",
    "black_knight": "BN",
    "black_pawn": "BP",
}

# Preferred class-name mapping. We resolve pieces by class name so models
# trained with different class index orders still work in play.py.
NAME_TO_PIECE = {
    "white_queen": (chess.QUEEN, chess.WHITE),
    "white_king": (chess.KING, chess.WHITE),
    "white_rook": (chess.ROOK, chess.WHITE),
    "white_bishop": (chess.BISHOP, chess.WHITE),
    "white_knight": (chess.KNIGHT, chess.WHITE),
    "white_pawn": (chess.PAWN, chess.WHITE),
    "black_queen": (chess.QUEEN, chess.BLACK),
    "black_king": (chess.KING, chess.BLACK),
    "black_rook": (chess.ROOK, chess.BLACK),
    "black_bishop": (chess.BISHOP, chess.BLACK),
    "black_knight": (chess.KNIGHT, chess.BLACK),
    "black_pawn": (chess.PAWN, chess.BLACK),
}

PIECE_TYPE_TO_NAME = {
    chess.PAWN: "pawn",
    chess.KNIGHT: "knight",
    chess.BISHOP: "bishop",
    chess.ROOK: "rook",
    chess.QUEEN: "queen",
    chess.KING: "king",
}

ALL_SQUARES = [chess.square_name(sq) for sq in chess.SQUARES]


#: FEN single-letter class labels, as used by the robochess-phase-2 Roboflow
#: model. Colour is encoded by CASE: "R" is a white rook, "r" a black one.
FEN_LETTER_TO_TYPE = {
    "p": "pawn", "n": "knight", "b": "bishop",
    "r": "rook", "q": "queen", "k": "king",
}


def normalize_class_name(name: str) -> str:
    """Normalize class labels from various datasets into canonical names."""
    raw = str(name).strip()
    # Single-letter FEN labels must be resolved BEFORE lowercasing, which would
    # otherwise collapse "R" and "r" into the same string and silently discard
    # the colour -- leaving every detection unmappable.
    if len(raw) == 1 and raw.lower() in FEN_LETTER_TO_TYPE:
        color = "white" if raw.isupper() else "black"
        return f"{color}_{FEN_LETTER_TO_TYPE[raw.lower()]}"
    cleaned = raw.lower().replace(" ", "_").replace("-", "_")
    # Common dataset typo seen in some Roboflow exports.
    cleaned = cleaned.replace("qawn", "pawn")
    return cleaned


def piece_label_from_piece(piece: chess.Piece) -> str:
    color = "white" if piece.color == chess.WHITE else "black"
    type_name = PIECE_TYPE_TO_NAME.get(piece.piece_type, "unknown")
    return f"{color}_{type_name}"


def parse_piece_label(label: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    if not label:
        return None, None
    cleaned = normalize_class_name(str(label))
    parts = cleaned.split("_")
    if len(parts) < 2:
        return None, None
    color = parts[0]
    type_name = "_".join(parts[1:])
    return color, type_name


def order_points(pts):
    """Order 4 points as: top-left, top-right, bottom-right, bottom-left."""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def parse_cloud_model_id(model_ref: str) -> Optional[str]:
    """Return a Roboflow cloud model ID if the input looks like one."""
    text = str(model_ref).strip()
    if not text:
        return None
    if text.lower().startswith("rf://"):
        model_id = text[5:].strip()
        return model_id or None
    if text.lower().startswith(("http://", "https://")):
        parsed = urlparse(text)
        parts = [part for part in parsed.path.split("/") if part]
        return "/".join(parts[-2:]) if len(parts) >= 2 else None
    # Allow plain project/version format, e.g. chess-yimaf-jwsta/3
    if "/" in text and "\\" not in text and ":" not in text and not text.lower().endswith(".pt"):
        return text
    return None


class BoardRecognizer:
    """
    Converts camera frames to chess board state using YOLO piece detection.

    Workflow:
      1. calibrate(corners) — set the 4 board corners for perspective transform
      2. detect(frame) — run YOLO + return list of detections
      3. frame_to_fen(frame) — full pipeline: detect → map to squares → FEN
      4. infer_move(prev_fen, curr_fen, turn) — compare two states to find the move
    """

    BOARD_SIZE = 896  # warped board resolution for higher-detail inference

    def __init__(self, model_path: str = "models/best.pt", confidence: float = 0.05):
        """
        Args:
            model_path: Path to trained YOLO .pt weights.
            confidence: Minimum detection confidence threshold.
        """
        self.model_ref = str(model_path).strip()
        self.vision_mode = os.getenv("ROBOCHESS_VISION_MODE", "auto").strip().lower()
        self.cloud_only = self.vision_mode == "cloud"
        self.roboflow_model_url = (
            os.getenv("ROBOCHESS_ROBOFLOW_MODEL_URL", "").strip()
            or os.getenv("ROBOFLOW_MODEL_URL", "").strip()
        )
        self.cloud_api_key = (
            os.getenv("ROBOCHESS_ROBOFLOW_API_KEY", "").strip()
            or os.getenv("ROBOFLOW_API_KEY", "").strip()
        )
        configured_cloud = os.getenv("ROBOCHESS_ROBOFLOW_ENABLED", "0").strip().lower() in {
            "1", "true", "yes", "on"
        }
        model_id = (
            parse_cloud_model_id(self.roboflow_model_url)
            or parse_cloud_model_id(self.model_ref)
        )
        self.roboflow_enabled = (
            self.cloud_only
            or configured_cloud
            or bool(model_id and self.cloud_api_key)
        )
        self.cloud_model_id = model_id if self.roboflow_enabled else None
        self.model_path: Optional[Path] = (
            None if self.cloud_only else (Path(self.model_ref) if self.model_ref else None)
        )
        self.confidence = confidence
        self.infer_iou = 0.45
        self.infer_max_det = 96
        # Use 640 to match default YOLO training resolution.
        # Overridden after model load if model metadata reports a different size.
        self.infer_imgsz = 640
        self.infer_augment = False
        self.model: Optional[object] = None
        self.cloud_model = None
        self.cloud_api_key = (
            os.getenv("ROBOCHESS_ROBOFLOW_API_KEY", "").strip()
            or os.getenv("ROBOFLOW_API_KEY", "").strip()
        )
        self.cloud_base_url = self._cloud_base_url(self.roboflow_model_url)
        self.warp_matrix: Optional[np.ndarray] = None
        self.model_names: dict[int, str] = {}
        self.last_error: Optional[str] = None
        self.active_detector = "none"

        # Keep both candidates loaded when possible. Cloud is preferred at
        # inference time; local YOLO remains available for offline fallback.
        if self.roboflow_enabled and self.cloud_model_id:
            try:
                self._load_cloud_model()
            except Exception as exc:
                self.last_error = str(exc)
                print(f"[WARN] Roboflow unavailable: {exc}")
        if not self.cloud_only and self.model_path and self.model_path.is_file():
            try:
                self._load_local_model()
            except Exception as exc:
                self.last_error = str(exc)
                print(f"[WARN] Local model unavailable: {exc}")
        if not self.is_ready:
            if self.cloud_only:
                print("[WARN] Cloud vision is not ready. Configure ROBOCHESS_ROBOFLOW_MODEL_URL and ROBOCHESS_ROBOFLOW_API_KEY.")
            else:
                print(f"[WARN] No vision model is ready. Configure Roboflow or install local weights at {self.model_ref}.")

    @staticmethod
    def _cloud_base_url(model_url: str) -> str:
        parsed = urlparse(model_url)
        if parsed.scheme and parsed.netloc:
            return f"{parsed.scheme}://{parsed.netloc}"
        return "https://detect.roboflow.com"

    def _load_cloud_model(self) -> None:
        if not self.cloud_api_key or not self.cloud_base_url:
            raise RuntimeError(
                "Roboflow is enabled but ROBOCHESS_ROBOFLOW_MODEL_URL/API_KEY is missing."
            )
        self.cloud_model = {
            "model_id": self.cloud_model_id,
            "api_key": self.cloud_api_key,
            "base_url": self.cloud_base_url,
        }
        self.model_names = {i: name for i, name in enumerate(CLASS_NAMES)}
        print(f"[OK] Roboflow cloud model configured: {self.cloud_model_id}")

    def _load_local_model(self) -> None:
        if YOLO is None:
            raise ImportError("ultralytics is required for local .pt models: pip install ultralytics")
        if self.model_path is None:
            raise FileNotFoundError("Local model path is not set.")
        self.model = YOLO(str(self.model_path))
        raw_names = getattr(self.model, "names", None)
        if isinstance(raw_names, dict):
            self.model_names = {int(k): normalize_class_name(str(v)) for k, v in raw_names.items()}
        elif isinstance(raw_names, list):
            self.model_names = {i: normalize_class_name(str(v)) for i, v in enumerate(raw_names)}
        try:
            trained_sz = int((getattr(self.model, "overrides", {}) or {}).get("imgsz", 0))
            if trained_sz >= 320:
                self.infer_imgsz = trained_sz
        except Exception:
            pass
        print(f"[OK] Local YOLO model loaded: {self.model_path} (infer_imgsz={self.infer_imgsz})")

    def _load_model(self):
        """Load a local YOLO model or a Roboflow cloud model."""
        if self.cloud_model_id is not None:
            self._load_cloud_model()
            return
        self._load_local_model()

    def load_model(self, path: Optional[str] = None):
        """Explicitly load or reload the model."""
        if path:
            self.model_ref = str(path).strip()
            self.cloud_model_id = (
                parse_cloud_model_id(self.roboflow_model_url)
                or parse_cloud_model_id(self.model_ref)
                if self.roboflow_enabled
                else None
            )
            self.model_path = (
                None
                if self.cloud_only or self.cloud_model_id
                else Path(self.model_ref)
            )
        if self.cloud_model_id is None:
            if self.model_path is None or not self.model_path.exists():
                raise FileNotFoundError(f"Model not found: {self.model_ref}")
        self._load_model()

    @property
    def is_ready(self) -> bool:
        """Check if the model is loaded and corners are calibrated."""
        return self.model is not None or self.cloud_model is not None

    def status(self) -> dict:
        return {
            "ready": self.is_ready,
            "vision_mode": self.vision_mode,
            "active_detector": self.active_detector if self.is_ready else "none",
            "cloud_configured": self.cloud_model is not None,
            "local_model_configured": self.model_path is not None,
            "local_model_available": self.model is not None,
            "model_path": str(self.model_path) if self.model_path else None,
            "last_error": self.last_error,
        }

    @property
    def is_calibrated(self) -> bool:
        """Check if board corners have been set."""
        return self.warp_matrix is not None

    # ─── Calibration ──────────────────────────────────────────

    def calibrate(self, corners: list[tuple[float, float]]):
        """
        Set the 4 board corners for perspective transformation.

        Args:
            corners: List of 4 (x, y) tuples in order:
                     top-left, top-right, bottom-right, bottom-left
                     (of the a8 corner looking from white's perspective).
        """
        if len(corners) != 4:
            raise ValueError("Exactly 4 corner points required")

        pts = np.array(corners, dtype="float32")
        rect = order_points(pts)
        dst = np.array([
            [0, 0],
            [self.BOARD_SIZE - 1, 0],
            [self.BOARD_SIZE - 1, self.BOARD_SIZE - 1],
            [0, self.BOARD_SIZE - 1]
        ], dtype="float32")
        self.warp_matrix = cv2.getPerspectiveTransform(rect, dst)
        print(f"[OK] Board calibrated with corners: {corners}")

    def warp_frame(self, frame: np.ndarray) -> np.ndarray:
        """Apply perspective transform to get a top-down board view."""
        if self.warp_matrix is not None:
            return cv2.warpPerspective(frame, self.warp_matrix,
                                       (self.BOARD_SIZE, self.BOARD_SIZE))
        # Fall back to simple resize if not calibrated
        return cv2.resize(frame, (self.BOARD_SIZE, self.BOARD_SIZE))

    # ─── Detection ────────────────────────────────────────────

    def detect(self, frame: np.ndarray) -> list[dict]:
        """
        Run YOLO detection on a frame.

        Args:
            frame: BGR image (raw camera frame or warped board).

        Returns:
            List of detections, each a dict with:
              - class_id (int)
              - class_name (str)
              - confidence (float)
              - bbox (list[float]) — [x1, y1, x2, y2] pixel coords
              - center (tuple[float, float]) — (cx, cy)
        """
        if self.cloud_model is None and self.model is None:
            raise RuntimeError("Model not loaded. Call load_model() first.")

        if self.cloud_model is not None:
            try:
                detections = self._detect_cloud(frame)
                self.active_detector = "roboflow"
                self.last_error = None
                return detections
            except Exception as exc:
                fallback = "no local fallback configured" if self.cloud_only else "using local model"
                self.last_error = f"Roboflow inference failed; {fallback}: {exc}"
                if self.model is None:
                    raise RuntimeError(self.last_error) from exc
        if self.model is not None:
            detections = self._detect_local(frame)
            self.active_detector = "local_yolo"
            return detections
        raise RuntimeError("No vision detector is available")

    def _detect_local(self, frame: np.ndarray) -> list[dict]:
        """Run local Ultralytics inference."""
        if self.model is None:
            raise RuntimeError("Local model is not loaded.")

        results = self.model.predict(
            source=frame,
            conf=self.confidence,
            iou=self.infer_iou,
            imgsz=self.infer_imgsz,
            max_det=self.infer_max_det,
            classes=list(range(len(CLASS_NAMES))),
            augment=self.infer_augment,
            verbose=False,
        )
        detections = []
        frame_area = float(frame.shape[0] * frame.shape[1])

        for r in results:
            boxes = r.boxes
            if boxes is None:
                continue
            for i in range(len(boxes)):
                cls_id = int(boxes.cls[i].item())
                conf = float(boxes.conf[i].item())
                x1, y1, x2, y2 = boxes.xyxy[i].tolist()
                bw = max(1.0, x2 - x1)
                bh = max(1.0, y2 - y1)
                box_area = bw * bh
                aspect = bw / bh

                # Filter improbable boxes to suppress off-piece hallucinations.
                # Min: a piece must cover at least 0.03% of the warped frame.
                # Max: a piece should not cover more than 15% of the frame.
                if box_area < frame_area * 0.0003 or box_area > frame_area * 0.15:
                    continue
                # Allow taller/wider aspect ratios than default (pieces vary a lot).
                if aspect < 0.18 or aspect > 3.5:
                    continue

                cx = (x1 + x2) / 2
                cy = (y1 + y2) / 2
                class_name = self.model_names.get(
                    cls_id,
                    CLASS_NAMES[cls_id] if cls_id < len(CLASS_NAMES) else f"unknown_{cls_id}",
                )
                class_name = normalize_class_name(class_name)
                detections.append({
                    "class_id": cls_id,
                    "class_name": class_name,
                    "confidence": round(conf, 4),
                    "bbox": [round(v, 1) for v in [x1, y1, x2, y2]],
                    "center": (round(cx, 1), round(cy, 1)),
                })

        return detections

    def _detect_cloud(self, frame: np.ndarray) -> list[dict]:
        """Run Roboflow cloud inference and normalize outputs."""
        if self.cloud_model is None:
            raise RuntimeError("Cloud model is not loaded.")

        ok, encoded = cv2.imencode(".jpg", frame)
        if not ok:
            raise RuntimeError("Failed to encode frame for cloud inference.")

        model_id = str(self.cloud_model["model_id"])
        api_key = str(self.cloud_model["api_key"])
        base_url = str(self.cloud_model["base_url"])
        url = f"{base_url}/{model_id}"
        conf_float = max(0.0, min(1.0, float(self.confidence)))
        conf_percent = int(round(conf_float * 100.0))

        # Try both confidence formats because some Roboflow endpoints expect
        # percentages (0-100) and others accept normalized values (0-1).
        param_options = [
            {"api_key": api_key, "confidence": conf_percent, "format": "json"},
            {"api_key": api_key, "confidence": conf_float, "format": "json"},
        ]

        # Try multipart first, then raw bytes fallback for compatibility.
        response = None
        last_error = None
        timeout_sec = float(os.getenv("ROBOCHESS_ROBOFLOW_TIMEOUT_SECONDS", os.getenv("ROBOFLOW_TIMEOUT", "20")))
        max_retries = max(0, int(os.getenv("ROBOCHESS_ROBOFLOW_RETRIES", os.getenv("ROBOFLOW_RETRIES", "0"))))
        for attempt in range(max_retries + 1):
            for params in param_options:
                for send_mode in ("multipart", "raw"):
                    try:
                        if send_mode == "multipart":
                            http_resp = requests.post(
                                url,
                                params=params,
                                files={"file": ("frame.jpg", encoded.tobytes(), "image/jpeg")},
                                timeout=timeout_sec,
                            )
                        else:
                            http_resp = requests.post(
                                url,
                                params=params,
                                data=encoded.tobytes(),
                                headers={"Content-Type": "application/octet-stream"},
                                timeout=timeout_sec,
                            )
                        http_resp.raise_for_status()
                        response = http_resp.json()
                        break
                    except Exception as exc:
                        last_error = exc
                if response is not None:
                    break
            if response is not None:
                break
            if attempt < max_retries:
                time.sleep(0.4 * (attempt + 1))

        if response is None:
            raise RuntimeError(f"Cloud inference failed: {last_error}")

        if isinstance(response, list):
            response = response[0] if response else {}
        predictions = response.get("predictions", []) if isinstance(response, dict) else []
        detections = []
        frame_area = float(frame.shape[0] * frame.shape[1])

        for pred in predictions:
            conf = float(pred.get("confidence", 0.0))
            if conf < self.confidence:
                continue

            cx = float(pred.get("x", 0.0))
            cy = float(pred.get("y", 0.0))
            bw = max(1.0, float(pred.get("width", 0.0)))
            bh = max(1.0, float(pred.get("height", 0.0)))

            x1 = cx - (bw / 2.0)
            y1 = cy - (bh / 2.0)
            x2 = cx + (bw / 2.0)
            y2 = cy + (bh / 2.0)

            box_area = bw * bh
            aspect = bw / bh
            if box_area < frame_area * 0.0003 or box_area > frame_area * 0.15:
                continue
            if aspect < 0.18 or aspect > 3.5:
                continue

            class_name = normalize_class_name(str(pred.get("class", "")))
            raw_cls = pred.get("class_id", -1)
            try:
                cls_id = int(raw_cls)
            except Exception:
                cls_id = -1
            if cls_id < 0 and class_name in CLASS_NAMES:
                cls_id = CLASS_NAMES.index(class_name)

            detections.append(
                {
                    "class_id": cls_id,
                    "class_name": class_name,
                    "confidence": round(conf, 4),
                    "bbox": [round(v, 1) for v in [x1, y1, x2, y2]],
                    "center": (round(cx, 1), round(cy, 1)),
                }
            )

        return detections

    # ─── Square Mapping ───────────────────────────────────────

    def _center_to_square(self, cx: float, cy: float,
                          frame_w: int, frame_h: int) -> Optional[str]:
        """
        Map a detection center (cx, cy) to a chess square name.

        Assumes the frame is a top-down board view with a1 at bottom-left
        (white's perspective: rank 1 at bottom, file a on the left).

        Args:
            cx, cy: Center of detected piece in pixel coordinates.
            frame_w, frame_h: Frame dimensions.

        Returns:
            Square name like "e4", or None if out of bounds.
        """
        file_idx = int(cx / (frame_w / 8))
        rank_idx = int(cy / (frame_h / 8))
        file_idx = max(0, min(7, file_idx))
        rank_idx = max(0, min(7, rank_idx))

        # Convert: rank_idx=0 → rank 8 (top of image), rank_idx=7 → rank 1 (bottom)
        file_char = chr(ord('a') + file_idx)
        rank_num = 8 - rank_idx
        return f"{file_char}{rank_num}"

    def detections_to_board(self, detections: list[dict],
                            frame_w: int, frame_h: int) -> chess.Board:
        """
        Convert a list of YOLO detections to a chess.Board.

        When multiple pieces map to the same square, the highest-confidence
        detection wins.
        """
        board = chess.Board(fen=None)  # empty board
        board.clear()

        # Track best confidence per square to resolve conflicts
        square_best: dict[str, tuple[float, int]] = {}  # sq → (conf, class_id)

        for det in detections:
            cx, cy = det["center"]
            sq_name = self._center_to_square(cx, cy, frame_w, frame_h)
            if sq_name is None:
                continue

            conf = det["confidence"]
            cls_name = normalize_class_name(str(det.get("class_name", "")))
            if sq_name not in square_best or conf > square_best[sq_name][0]:
                square_best[sq_name] = (conf, cls_name, det["class_id"])

        # Place pieces
        for sq_name, (conf, cls_name, cls_id) in square_best.items():
            if cls_name in NAME_TO_PIECE:
                piece_type, color = NAME_TO_PIECE[cls_name]
            elif cls_id in CLASS_MAP:
                # Backward-compatible fallback for older models with expected IDs.
                piece_type, color = CLASS_MAP[cls_id]
            else:
                continue
            sq = chess.parse_square(sq_name)
            board.set_piece_at(sq, chess.Piece(piece_type, color))

        return board

    def detections_to_state_dict(
        self,
        detections: list[dict],
        frame_w: int,
        frame_h: int,
        min_confidence: float = 0.60,
    ) -> dict[str, Optional[str]]:
        """Convert detections to a square->piece-name dict with confidence filtering."""
        state: dict[str, Optional[str]] = {sq: None for sq in ALL_SQUARES}
        square_best: dict[str, tuple[float, str]] = {}

        for det in detections:
            conf = float(det.get("confidence", 0.0))
            if conf < float(min_confidence):
                continue
            cx, cy = det.get("center", (None, None))
            if cx is None or cy is None:
                continue
            sq_name = self._center_to_square(float(cx), float(cy), frame_w, frame_h)
            if sq_name is None:
                continue
            class_name = normalize_class_name(str(det.get("class_name", "")))
            if not class_name:
                continue
            existing = square_best.get(sq_name)
            if existing is None or conf > existing[0]:
                square_best[sq_name] = (conf, class_name)

        for sq_name, (_, class_name) in square_best.items():
            state[sq_name] = class_name
        return state

    def state_dict_to_board(self, state: dict[str, Optional[str]]) -> chess.Board:
        """Convert a square->piece-name dict into a chess.Board."""
        board = chess.Board(fen=None)
        board.clear()
        for sq_name, label in state.items():
            if not label:
                continue
            class_name = normalize_class_name(str(label))
            if class_name in NAME_TO_PIECE:
                piece_type, color = NAME_TO_PIECE[class_name]
            else:
                continue
            sq = chess.parse_square(sq_name)
            board.set_piece_at(sq, chess.Piece(piece_type, color))
        return board

    def board_to_state_dict(self, board: chess.Board) -> dict[str, Optional[str]]:
        """Convert a chess.Board into a square->piece-name dict."""
        state: dict[str, Optional[str]] = {sq: None for sq in ALL_SQUARES}
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece is None:
                continue
            sq_name = chess.square_name(sq)
            state[sq_name] = piece_label_from_piece(piece)
        return state

    def to_occupancy_state(self, state: dict[str, Optional[str]]) -> dict[str, bool]:
        """Convert a square->piece-name dict into a square->occupied dict."""
        return {sq: bool(label) for sq, label in state.items()}

    def board_to_occupancy_state(self, board: chess.Board) -> dict[str, bool]:
        """Convert a chess.Board into a square->occupied dict."""
        state: dict[str, bool] = {sq: False for sq in ALL_SQUARES}
        for sq in chess.SQUARES:
            state[chess.square_name(sq)] = board.piece_at(sq) is not None
        return state

    def expected_initial_state(self) -> dict[str, Optional[str]]:
        """Return the canonical initial chess position as a state dict."""
        return self.board_to_state_dict(chess.Board())

    def validate_initial_state(
        self,
        curr_state: dict[str, Optional[str]],
        max_missing: int = 4,
        max_extra: int = 2,
    ) -> tuple[bool, list[str]]:
        """Validate the starting position with tolerant same-color matching."""
        expected = self.expected_initial_state()
        mismatches: list[str] = []
        color_mismatches = 0
        missing = 0
        extra = 0
        for sq in ALL_SQUARES:
            expected_label = expected.get(sq)
            curr_label = curr_state.get(sq)
            if expected_label is None and curr_label is None:
                continue
            if expected_label is None and curr_label is not None:
                extra += 1
                mismatches.append(sq)
                continue
            if expected_label is not None and curr_label is None:
                missing += 1
                mismatches.append(sq)
                continue
            exp_color, _ = parse_piece_label(expected_label)
            curr_color, _ = parse_piece_label(curr_label)
            if exp_color != curr_color:
                color_mismatches += 1
                mismatches.append(sq)

        valid = (missing <= max_missing) and (extra <= max_extra) and (color_mismatches == 0)
        return valid, mismatches

    @staticmethod
    def is_same_piece(piece_a: Optional[str], piece_b: Optional[str]) -> bool:
        """Tolerant matching: exact or same type, but never different colors."""
        if not piece_a and not piece_b:
            return True
        if not piece_a or not piece_b:
            return False
        color_a, type_a = parse_piece_label(piece_a)
        color_b, type_b = parse_piece_label(piece_b)
        if not color_a or not color_b or not type_a or not type_b:
            return False
        if color_a != color_b:
            return False
        return type_a == type_b

    def match_score(
        self,
        simulated_state: dict[str, Optional[str]],
        curr_state: dict[str, Optional[str]],
    ) -> int:
        score = 0
        for sq in ALL_SQUARES:
            if self.is_same_piece(simulated_state.get(sq), curr_state.get(sq)):
                score += 1
        return score

    def match_score_occupancy(
        self,
        simulated_state: dict[str, bool],
        curr_state: dict[str, bool],
    ) -> int:
        score = 0
        for sq in ALL_SQUARES:
            if simulated_state.get(sq, False) == curr_state.get(sq, False):
                score += 1
        return score

    def infer_move_from_state(
        self,
        prev_board: chess.Board,
        curr_state: dict[str, Optional[str]],
        min_score: int = 60,
        min_gap: int = 4,
    ) -> tuple[Optional[chess.Move], int, int]:
        """Simulate all legal moves and return the best match to current state."""
        best_move: Optional[chess.Move] = None
        best_score = -1
        second_best = -1

        for move in prev_board.legal_moves:
            test_board = prev_board.copy(stack=False)
            test_board.push(move)
            simulated_state = self.board_to_state_dict(test_board)
            score = self.match_score(simulated_state, curr_state)
            if score > best_score:
                second_best = best_score
                best_score = score
                best_move = move
            elif score > second_best:
                second_best = score

        if best_move is None:
            return None, best_score, second_best

        if best_score < min_score or (best_score - second_best) < min_gap:
            return None, best_score, second_best

        return best_move, best_score, second_best

    def infer_move_from_occupancy(
        self,
        prev_board: chess.Board,
        curr_state: dict[str, bool],
        min_score: int = 60,
        min_gap: int = 4,
    ) -> tuple[Optional[chess.Move], int, int]:
        """Simulate all legal moves and return the best occupancy match."""
        best_move: Optional[chess.Move] = None
        best_score = -1
        second_best = -1

        for move in prev_board.legal_moves:
            test_board = prev_board.copy(stack=False)
            test_board.push(move)
            simulated_state = self.board_to_occupancy_state(test_board)
            score = self.match_score_occupancy(simulated_state, curr_state)
            if score > best_score:
                second_best = best_score
                best_score = score
                best_move = move
            elif score > second_best:
                second_best = score

        if best_move is None:
            return None, best_score, second_best

        if best_score < min_score or (best_score - second_best) < min_gap:
            return None, best_score, second_best

        return best_move, best_score, second_best

    # ─── Full Pipeline ────────────────────────────────────────

    def frame_to_fen(self, frame: np.ndarray) -> tuple[str, list[dict]]:
        """
        Full pipeline: warp frame → detect pieces → build board → return FEN.

        Args:
            frame: Raw camera frame (BGR).

        Returns:
            Tuple of (FEN string, list of detections).
        """
        warped = self.warp_frame(frame)
        detections = self.detect(warped)
        board = self.detections_to_board(
            detections, warped.shape[1], warped.shape[0]
        )
        return board.board_fen(), detections

    def detect_from_image(self, frame: np.ndarray) -> tuple[str, list[dict], np.ndarray]:
        """
        Like frame_to_fen but also returns the warped image for visualization.
        """
        warped = self.warp_frame(frame)
        detections = self.detect(warped)
        board = self.detections_to_board(
            detections, warped.shape[1], warped.shape[0]
        )
        return board.board_fen(), detections, warped

    # ─── Move Inference ───────────────────────────────────────

    @staticmethod
    def infer_move(prev_fen: str, curr_fen: str,
                   turn: chess.Color = chess.WHITE) -> Optional[chess.Move]:
        """
        Compare two board-only FENs and find the legal move that transforms
        prev into curr.

        Args:
            prev_fen: Board FEN before the move (pieces only, e.g. from board_fen()).
            curr_fen: Board FEN after the move.
            turn: Whose turn it was (WHITE or BLACK).

        Returns:
            The chess.Move if found among legal moves, else None.
        """
        # Build full FEN with turn and castling
        turn_char = "w" if turn == chess.WHITE else "b"
        prev_board = chess.Board(f"{prev_fen} {turn_char} KQkq - 0 1")
        curr_board = chess.Board(f"{curr_fen} {turn_char} KQkq - 0 1")

        # Try each legal move — see which one produces the target position
        for move in prev_board.legal_moves:
            test_board = prev_board.copy()
            test_board.push(move)
            if test_board.board_fen() == curr_board.board_fen():
                return move

        return None

    # ─── Visualization ────────────────────────────────────────

    def draw_detections(
        self,
        frame: np.ndarray,
        detections: list[dict],
        line_thickness: int = 1,
        label_scale: float = 0.36,
        label_thickness: int = 1,
    ) -> np.ndarray:
        """Draw bounding boxes and labels on a frame."""
        vis = frame.copy()

        # Keep the overlay stable: one displayed detection per square (highest confidence).
        square_best: dict[str, dict] = {}
        h, w = vis.shape[:2]
        for det in detections:
            cx, cy = det["center"]
            sq = self._center_to_square(cx, cy, w, h)
            if sq is None:
                continue
            curr = square_best.get(sq)
            if curr is None or float(det["confidence"]) > float(curr["confidence"]):
                square_best[sq] = det

        for sq_name, det in square_best.items():
            x1, y1, x2, y2 = [int(v) for v in det["bbox"]]
            name = det["class_name"]
            conf = det["confidence"]

            # Tight, piece-sized box rather than a full-square box.
            width = max(1, x2 - x1)
            height = max(1, y2 - y1)
            shrink_x = int(width * 0.28)
            shrink_y = int(height * 0.28)
            x1 = max(0, x1 + shrink_x)
            y1 = max(0, y1 + shrink_y)
            x2 = min(vis.shape[1] - 1, x2 - shrink_x)
            y2 = min(vis.shape[0] - 1, y2 - shrink_y)

            if x2 <= x1:
                x2 = min(vis.shape[1] - 1, x1 + 4)
            if y2 <= y1:
                y2 = min(vis.shape[0] - 1, y1 + 4)

            color = DISPLAY_COLORS.get(name, (0, 220, 255))
            text_color = (10, 10, 10) if name.startswith("white") else (245, 245, 245)

            # Corner-bracket style box to reduce visual clutter.
            thickness = max(1, int(line_thickness))
            corner = max(5, min(width, height) // 5)
            cv2.line(vis, (x1, y1), (x1 + corner, y1), color, thickness)
            cv2.line(vis, (x1, y1), (x1, y1 + corner), color, thickness)
            cv2.line(vis, (x2, y1), (x2 - corner, y1), color, thickness)
            cv2.line(vis, (x2, y1), (x2, y1 + corner), color, thickness)
            cv2.line(vis, (x1, y2), (x1 + corner, y2), color, thickness)
            cv2.line(vis, (x1, y2), (x1, y2 - corner), color, thickness)
            cv2.line(vis, (x2, y2), (x2 - corner, y2), color, thickness)
            cv2.line(vis, (x2, y2), (x2, y2 - corner), color, thickness)

            code = DISPLAY_CODES.get(name, name[:2].upper())
            label = code
            (tw, th), _ = cv2.getTextSize(
                label,
                cv2.FONT_HERSHEY_SIMPLEX,
                float(label_scale),
                max(1, int(label_thickness)),
            )
            label_y = max(th + 4, y1 - 5)
            label_x2 = min(vis.shape[1] - 1, x1 + tw + 6)
            cv2.rectangle(vis, (x1, label_y - th - 4), (label_x2, label_y + 2), color, -1)
            cv2.putText(
                vis,
                label,
                (x1 + 3, label_y),
                cv2.FONT_HERSHEY_SIMPLEX,
                float(label_scale),
                text_color,
                max(1, int(label_thickness)),
            )

        return vis

    def draw_board_grid(
        self,
        frame: np.ndarray,
        color: tuple[int, int, int] = (60, 60, 60),
        thickness: int = 1,
    ) -> np.ndarray:
        """Draw an 8×8 grid overlay on a warped board frame."""
        vis = frame.copy()
        h, w = vis.shape[:2]
        sw, sh = w // 8, h // 8

        for i in range(9):
            cv2.line(vis, (i * sw, 0), (i * sw, h), color, thickness)
            cv2.line(vis, (0, i * sh), (w, i * sh), color, thickness)
        return vis
