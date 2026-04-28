import asyncio
import base64
from collections import Counter

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, BackgroundTasks
import chess
import cv2
import numpy as np

from backend.api.schemas import (
    ApiResponse,
    GameMoveRequest,
    GameStartRequest,
    ManualCalibrationRequest,
    ModelLoadRequest,
    MoveAiRequest,
)
from backend.core.game_manager import GameManager
from backend.db.client import get_db
from backend.services.calibration_service import validate_initial_board
from backend.services.detection_service import (
    detect_board_state,
    detect_board_state_from_frame,
)
from backend.services.engine_service import get_ai_move
from backend.services.game_service import (
    create_game,
    end_game,
    get_game_state,
    get_moves_since,
    record_move,
    validate_and_record_move,
)
from backend.services.move_service import detect_move
from backend.utils.helpers import error, ok
from backend.realtime.manager import manager as ws_manager

router = APIRouter()

HAND_SKIN_MOTION_THRESHOLD = 0.004
HAND_MIN_BLOB_RATIO = 0.0025


def _is_hand_present(frame, prev_gray=None):
    ycrcb = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb)
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    skin_mask = cv2.bitwise_or(
        cv2.inRange(
            ycrcb,
            np.array([0, 140, 90], dtype=np.uint8),
            np.array([255, 175, 125], dtype=np.uint8),
        ),
        cv2.inRange(
            hsv,
            np.array([0, 40, 60], dtype=np.uint8),
            np.array([20, 200, 255], dtype=np.uint8),
        ),
    )
    kernel = np.ones((5, 5), np.uint8)
    skin_mask = cv2.morphologyEx(
        cv2.threshold(cv2.GaussianBlur(skin_mask, (7, 7), 0), 80, 255, cv2.THRESH_BINARY)[1],
        cv2.MORPH_CLOSE,
        kernel,
    )
    curr_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    if prev_gray is None:
        return False, 0.0, curr_gray, True

    _, motion_mask = cv2.threshold(
        cv2.absdiff(curr_gray, prev_gray), 28, 255, cv2.THRESH_BINARY
    )
    motion_mask = cv2.morphologyEx(motion_mask, cv2.MORPH_CLOSE, kernel)
    motion_skin = cv2.bitwise_and(motion_mask, skin_mask)
    frame_area = float(frame.shape[0] * frame.shape[1])
    skin_motion_ratio = cv2.countNonZero(motion_skin) / frame_area
    contours, _ = cv2.findContours(
        motion_skin, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    blob_ratio = max((cv2.contourArea(c) for c in contours), default=0.0) / frame_area
    present = (
        skin_motion_ratio >= HAND_SKIN_MOTION_THRESHOLD
        and blob_ratio >= HAND_MIN_BLOB_RATIO
    )
    return present, max(skin_motion_ratio, blob_ratio), curr_gray, False


def _state_signature(state: dict) -> tuple:
    return tuple((k, state.get(k)) for k in sorted(state.keys()))


async def _collect_stable_state(manager: GameManager,
                                attempts: int = 5,
                                delay_sec: float = 0.12):
    recognizer = manager.recognizer
    if recognizer is None or not recognizer.is_ready:
        return None, {"error": "Model not ready"}

    samples = []
    det_counts = []
    for _ in range(max(1, attempts)):
        try:
            frame = manager.capture_frame()
        except Exception as exc:
            return None, {"error": f"Camera capture failed: {exc}"}

        warped = recognizer.warp_frame(frame)
        hand_present, hand_ratio, curr_gray, warmup = _is_hand_present(
            warped, manager.hand_prev_gray
        )
        manager.hand_prev_gray = curr_gray

        if warmup:
            return None, {"warmup": True}
        if hand_present:
            return None, {
                "hand_present": True,
                "hand_ratio": round(float(hand_ratio), 4),
            }

        try:
            state, detections = detect_board_state_from_frame(manager, frame)
        except Exception as exc:
            return None, {"error": f"Detection failed: {exc}"}

        samples.append(state)
        det_counts.append(detections)
        await asyncio.sleep(delay_sec)

    if not samples:
        return None, {"error": "No samples"}

    signatures = Counter(_state_signature(s) for s in samples)
    best_sig, votes = signatures.most_common(1)[0]
    stable_state = next(s for s in samples if _state_signature(s) == best_sig)
    return stable_state, {
        "votes": votes,
        "samples": len(samples),
        "detections": max(det_counts) if det_counts else 0,
    }


@router.get("/health", response_model=ApiResponse)
def health() -> ApiResponse:
    manager = GameManager.get_instance()
    data = {
        "model_ready": manager.recognizer.is_ready if manager.recognizer else False,
        "engine_ready": manager.engine is not None,
        "camera_ready": manager.camera is not None and manager.camera.isOpened(),
        "calibrated": manager.calibrated,
    }
    return ok("ok", data)


@router.post("/model/load", response_model=ApiResponse)
def load_model(payload: ModelLoadRequest) -> ApiResponse:
    manager = GameManager.get_instance()
    try:
        if manager.recognizer is None:
            return error("Recognizer not available")
        manager.recognizer.load_model(payload.model_path)
    except Exception as exc:
        return error("Model load failed", {"detail": str(exc)})
    return ok("ok", {"model_ref": manager.recognizer.model_ref, "ready": manager.recognizer.is_ready})


@router.get("/model/status", response_model=ApiResponse)
def model_status() -> ApiResponse:
    manager = GameManager.get_instance()
    data = {
        "model_ready": manager.recognizer.is_ready if manager.recognizer else False,
        "calibrated": manager.recognizer.is_calibrated if manager.recognizer else False,
    }
    return ok("ok", data)


@router.post("/calibrate", response_model=ApiResponse)
def calibrate() -> ApiResponse:
    manager = GameManager.get_instance()
    try:
        state, detections = detect_board_state(manager)
    except Exception as exc:
        return error("Detection failed", {"detail": str(exc)})

    valid, mismatches = validate_initial_board(state, manager.recognizer, manager.settings)
    if not valid:
        return error("Board not in valid starting position", {"mismatches": mismatches})

    with manager.state_lock:
        manager.board.reset()
        manager.prev_state = state
        manager.calibrated = True

    return ok("Calibration successful", {"detections": detections, "mismatches": []})


@router.post("/calibrate/auto", response_model=ApiResponse)
def calibrate_auto() -> ApiResponse:
    """
    Auto-detect the largest quadrilateral (the chessboard) in the camera frame
    and use it as calibration corners. Falls back to full-frame corners if
    detection fails so calibration always completes.
    """
    import numpy as np

    manager = GameManager.get_instance()
    try:
        frame = manager.capture_frame()
    except Exception as exc:
        return error("Camera capture failed", {"detail": str(exc)})

    height, width = frame.shape[:2]
    fallback = [(0.0, 0.0), (float(width - 1), 0.0),
                (float(width - 1), float(height - 1)), (0.0, float(height - 1))]
    detected_method = "full_frame_fallback"
    corners = fallback

    try:
        detected, method = _detect_board_corners(frame)
        if detected is not None:
            corners = detected
            detected_method = method
    except Exception:
        pass  # fall through to full-frame fallback

    try:
        manager.recognizer.calibrate(corners)
        manager.calibrated = True
    except Exception as exc:
        return error("Auto calibration failed", {"detail": str(exc)})

    return ok(
        "Auto calibration complete",
        {
            "corners": corners,
            "method": detected_method,
            "frame": {"width": width, "height": height},
        },
    )


def _detect_board_corners(frame) -> tuple:
    """
    Attempt to find the 4 corners of the chessboard in *frame*.

    Strategy (in order, first success wins):
      1. Largest quadrilateral from Canny + contour approx on gray image.
      2. Same on an adaptive-threshold version (handles varied lighting).
      3. Returns (None, "") when no good quad is found → caller falls back.

    Returns (list[tuple[float,float]] | None, str)
    """
    import numpy as np

    h, w = frame.shape[:2]
    min_area = (w * h) * 0.10   # board should occupy at least 10 % of frame
    max_area = (w * h) * 0.98   # but not the entire frame

    def _order_quad(pts):
        """Order 4 points: TL, TR, BR, BL."""
        pts = np.array(pts, dtype="float32")
        s = pts.sum(axis=1)
        d = np.diff(pts, axis=1)
        tl = pts[np.argmin(s)]
        br = pts[np.argmax(s)]
        tr = pts[np.argmin(d)]
        bl = pts[np.argmax(d)]
        return [(float(tl[0]), float(tl[1])),
                (float(tr[0]), float(tr[1])),
                (float(br[0]), float(br[1])),
                (float(bl[0]), float(bl[1]))]

    def _largest_quad_from_edges(edges):
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        best_area = 0
        best_quad = None
        for cnt in contours:
            area = cv2.contourArea(cnt)
            if area < min_area or area > max_area:
                continue
            peri = cv2.arcLength(cnt, True)
            approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
            if len(approx) == 4 and area > best_area:
                best_area = area
                best_quad = approx.reshape(4, 2)
        return best_quad

    # --- Pass 1: Canny on gray ------------------------------------------------
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(gray, 30, 120)
    edges = cv2.dilate(edges, None, iterations=2)
    quad = _largest_quad_from_edges(edges)
    if quad is not None:
        return _order_quad(quad), "canny_contour"

    # --- Pass 2: Adaptive threshold ------------------------------------------
    thresh = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
    )
    thresh = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE,
                               cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7)))
    thresh = cv2.Canny(thresh, 10, 60)
    thresh = cv2.dilate(thresh, None, iterations=2)
    quad = _largest_quad_from_edges(thresh)
    if quad is not None:
        return _order_quad(quad), "adaptive_thresh_contour"

    return None, ""


@router.post("/calibrate/manual", response_model=ApiResponse)
def calibrate_manual(payload: ManualCalibrationRequest) -> ApiResponse:
    manager = GameManager.get_instance()
    corners = payload.corners
    if len(corners) != 4:
        return error("Exactly 4 corner points required")
    try:
        manager.recognizer.calibrate([(float(c[0]), float(c[1])) for c in corners])
        manager.calibrated = True
    except Exception as exc:
        return error("Manual calibration failed", {"detail": str(exc)})
    return ok("Manual calibration complete", {"corners": corners})


@router.get("/calibrate/frame", response_model=ApiResponse)
def calibrate_frame() -> ApiResponse:
    manager = GameManager.get_instance()
    try:
        frame = manager.capture_frame()
    except Exception as exc:
        return error("Camera capture failed", {"detail": str(exc)})

    ok_encode, buffer = cv2.imencode(".jpg", frame)
    if not ok_encode:
        return error("Failed to encode frame")
    payload = base64.b64encode(buffer.tobytes()).decode("ascii")
    height, width = frame.shape[:2]
    return ok("ok", {"image_base64": payload, "width": width, "height": height})


@router.get("/calibrate/preview", response_model=ApiResponse)
def calibrate_preview() -> ApiResponse:
    manager = GameManager.get_instance()

    if manager.camera is not None and manager.camera.isOpened():
        for _ in range(2):
            manager.camera.grab()

    try:
        frame = manager.capture_frame()
    except Exception as exc:
        return error("Camera capture failed", {"detail": str(exc)})

    recognizer = manager.recognizer
    if recognizer is None or not recognizer.is_ready:
        return error("Model not ready — call /model/load first")

    warped = recognizer.warp_frame(frame)
    try:
        detections = recognizer.detect(warped)
    except Exception as exc:
        return error("Detection failed", {"detail": str(exc)})

    conf_min = float(manager.settings.detection_confidence_min)
    preview_min = max(0.05, conf_min * 0.3)
    filtered = [
        det for det in detections if float(det.get("confidence", 0.0)) >= preview_min
    ]

    board_view = recognizer.draw_board_grid(
        warped.copy(), color=(180, 180, 180), thickness=2
    )
    board_view = recognizer.draw_detections(
        board_view,
        filtered,
        line_thickness=2,
        label_scale=0.45,
        label_thickness=2,
    )

    ok_encode, buffer = cv2.imencode(".jpg", board_view)
    if not ok_encode:
        return error("Failed to encode preview")

    payload = base64.b64encode(buffer.tobytes()).decode("ascii")
    height, width = board_view.shape[:2]
    return ok(
        "ok",
        {
            "image_base64": payload,
            "width": width,
            "height": height,
            "detections": len(filtered),
        },
    )


@router.post("/move/detect_if_clear", response_model=ApiResponse)
async def detect_move_if_clear(
    background_tasks: BackgroundTasks, db=Depends(get_db)
) -> ApiResponse:
    manager = GameManager.get_instance()
    if not manager.calibrated:
        return error("Not calibrated", {"detail": "Run /calibrate first"})

    try:
        frame = manager.capture_frame()
    except Exception as exc:
        return error("Camera capture failed", {"detail": str(exc)})

    recognizer = manager.recognizer
    if recognizer is None or not recognizer.is_ready:
        return error("Model not ready — call /model/load first")

    warped = recognizer.warp_frame(frame)
    hand_present, hand_ratio, curr_gray, warmup = _is_hand_present(
        warped, manager.hand_prev_gray
    )
    manager.hand_prev_gray = curr_gray

    if warmup:
        return ok("hand_warmup", {"hand_present": False, "warmup": True})
    if hand_present:
        return ok(
            "hand_present",
            {"hand_present": True, "hand_ratio": round(float(hand_ratio), 4)},
        )

    try:
        curr_state, detections = detect_board_state_from_frame(manager, frame)
    except Exception as exc:
        return error("Detection failed", {"detail": str(exc)})

    used_fallback = False

    if manager.prev_state is None:
        return error("No previous board state", {"detail": "Run /calibrate again"})

    move, best_score, second_best = detect_move(
        manager.prev_state,
        curr_state,
        manager.board,
        manager.recognizer,
        manager.settings,
    )

    if move is None:
        stable_state, meta = await _collect_stable_state(manager)
        if stable_state is None:
            if meta.get("warmup"):
                return ok("hand_warmup", {"hand_present": False, "warmup": True})
            if meta.get("hand_present"):
                return ok(
                    "hand_present",
                    {
                        "hand_present": True,
                        "hand_ratio": meta.get("hand_ratio", 0.0),
                    },
                )
            return error(
                "No legal move matched",
                {
                    "score": best_score,
                    "second_best": second_best,
                    "detections": detections,
                    "fallback": meta,
                },
            )

        move, best_score, second_best = detect_move(
            manager.prev_state,
            stable_state,
            manager.board,
            manager.recognizer,
            manager.settings,
        )
        if move is None:
            return error(
                "No legal move matched",
                {
                    "score": best_score,
                    "second_best": second_best,
                    "detections": meta.get("detections", detections),
                    "fallback": meta,
                },
            )
        curr_state = stable_state
        detections = meta.get("detections", detections)
        used_fallback = True

    with manager.state_lock:
        if move not in manager.board.legal_moves:
            return error("Illegal move", {"uci": move.uci()})
        san = manager.board.san(move)
        manager.board.push(move)
        manager.prev_state = curr_state

    if manager.current_game_id:
        game_state, err = await record_move(
            db, manager.current_game_id, move.uci(), manager.get_fen()
        )
        if err:
            return error("Failed to persist move", {"detail": err})
        await ws_manager.send_to_game(
            manager.current_game_id,
            {
                "type": "game.move",
                "data": {
                    "game_id": manager.current_game_id,
                    "uci": move.uci(),
                    "fen": manager.get_fen(),
                    "game_version": game_state.get("game_version"),
                },
            },
        )

    if manager.mode == "human_vs_ai" and not manager.board.is_game_over():
        background_tasks.add_task(_trigger_ai_move, db)

    data = {
        "uci": move.uci(),
        "san": san,
        "fen": manager.get_fen(),
        "score": best_score,
        "second_best": second_best,
        "detections": detections,
        "fallback": used_fallback,
    }
    return ok("Move detected", data)


@router.post("/calibrate/validate", response_model=ApiResponse)
def calibrate_validate() -> ApiResponse:
    manager = GameManager.get_instance()

    # Flush stale camera buffer (read a few frames so we get the latest)
    if manager.camera is not None and manager.camera.isOpened():
        for _ in range(3):
            manager.camera.grab()

    try:
        state, detections = detect_board_state(manager)
    except Exception as exc:
        return error("Detection failed", {"detail": str(exc)})

    valid, mismatches = validate_initial_board(state, manager.recognizer, manager.settings)

    # Build rich per-square detail so the caller can see exactly what's wrong
    import chess as _chess
    expected_state = manager.recognizer.expected_initial_state()
    mismatch_detail = []
    for sq in mismatches:
        mismatch_detail.append({
            "square": sq,
            "expected": expected_state.get(sq),
            "detected": state.get(sq),
        })

    # Summarise counts for quick diagnosis
    missing = sum(1 for d in mismatch_detail if d["detected"] is None)
    extra   = sum(1 for d in mismatch_detail if d["expected"] is None)
    wrong   = len(mismatch_detail) - missing - extra

    if valid:
        with manager.state_lock:
            manager.board.reset()
            manager.prev_state = state
            manager.calibrated = True

    return ok("ok", {
        "valid": valid,
        "mismatches": mismatches,
        "mismatch_detail": mismatch_detail,
        "summary": {"missing": missing, "extra": extra, "wrong_color": wrong},
        "detections": detections,
        "pieces_detected": sum(1 for v in state.values() if v is not None),
        "pieces_expected": 32,
    })


@router.get("/calibrate/debug", response_model=ApiResponse)
def calibrate_debug() -> ApiResponse:
    """
    Diagnostic endpoint: captures a frame, runs YOLO at multiple
    confidence thresholds and returns a breakdown. Useful for diagnosing
    why validation always fails.
    """
    manager = GameManager.get_instance()

    # Flush camera buffer
    if manager.camera is not None and manager.camera.isOpened():
        for _ in range(3):
            manager.camera.grab()

    try:
        frame = manager.capture_frame()
    except Exception as exc:
        return error("Camera capture failed", {"detail": str(exc)})

    recognizer = manager.recognizer
    if recognizer is None or not recognizer.is_ready:
        return error("Model not ready — call /model/load first")

    warped = recognizer.warp_frame(frame)
    h, w = warped.shape[:2]

    # Raw detections at very low confidence so we see everything
    try:
        raw = recognizer.detect(warped)
    except Exception as exc:
        return error("Detection failed", {"detail": str(exc)})

    # Bucket by confidence
    def _count(thresh):
        return sum(1 for d in raw if d["confidence"] >= thresh)

    by_class = {}
    for d in raw:
        name = d["class_name"]
        by_class.setdefault(name, []).append(round(d["confidence"], 3))

    return ok("debug", {
        "warped_size": {"width": w, "height": h},
        "is_calibrated": recognizer.is_calibrated,
        "model_ref": recognizer.model_ref,
        "raw_detections_total": len(raw),
        "at_conf_0.05": _count(0.05),
        "at_conf_0.10": _count(0.10),
        "at_conf_0.25": _count(0.25),
        "at_conf_0.45": _count(0.45),
        "by_class": {k: {"count": len(v), "confidences": sorted(v, reverse=True)[:5]}
                     for k, v in by_class.items()},
        "top10_detections": sorted(raw, key=lambda d: d["confidence"], reverse=True)[:10],
        "tip": (
            "If raw_detections_total is 0, the model isn't detecting chess pieces — "
            "it hasn't been trained yet. Use /calibrate/force to proceed anyway."
            if len(raw) == 0 else
            "Detections found. If validation still fails, lower ROBOCHESS_DET_CONF "
            "or adjust calibration corners."
        ),
    })


@router.post("/calibrate/force", response_model=ApiResponse)
def calibrate_force() -> ApiResponse:
    """
    Force-mark the board as calibrated and validated, bypassing piece detection.
    Use this when the model isn't fully trained yet but you still want to test
    the rest of the pipeline.
    """
    manager = GameManager.get_instance()

    # Build an assumed-initial-position state from the expected board
    recognizer = manager.recognizer
    if recognizer is None:
        return error("Recognizer not available")

    assumed_state = recognizer.expected_initial_state()

    with manager.state_lock:
        manager.board.reset()
        manager.prev_state = assumed_state
        manager.calibrated = True

    return ok("Force-validated: assumed starting position", {
        "valid": True,
        "warning": "Position was NOT verified by the camera. "
                   "Piece detection accuracy depends on your trained model.",
    })




@router.post("/game/start", response_model=ApiResponse)
async def start_game(payload: GameStartRequest, db=Depends(get_db)) -> ApiResponse:
    manager = GameManager.get_instance()
    with manager.state_lock:
        manager.mode = payload.mode
        manager.difficulty = payload.difficulty
        manager.board.reset()
        manager.prev_state = None
        manager.calibrated = False
        manager.hand_prev_gray = None

    game = await create_game(db, manager.get_fen(), players=payload.players)
    manager.current_game_id = game.get("game_id")

    data = {
        "fen": manager.get_fen(),
        "turn": "white" if manager.board.turn == chess.WHITE else "black",
        "mode": manager.mode,
        "difficulty": manager.difficulty,
        "game_id": manager.current_game_id,
        "game_version": game.get("game_version", 0),
    }
    return ok("Game started", data)


@router.get("/game/state", response_model=ApiResponse)
async def game_state(game_id: str | None = None, db=Depends(get_db)) -> ApiResponse:
    manager = GameManager.get_instance()
    resolved_id = game_id or manager.current_game_id
    data = None
    if resolved_id:
        game, err = await get_game_state(db, resolved_id)
        if not err:
            data = {
                "fen": game.get("current_fen"),
                "turn": "white" if manager.board.turn == chess.WHITE else "black",
                "mode": manager.mode,
                "difficulty": manager.difficulty,
                "calibrated": manager.calibrated,
                "game_id": game.get("game_id"),
                "game_version": game.get("game_version"),
                "last_move": game.get("last_move"),
            }

    if data is None:
        data = {
            "fen": manager.get_fen(),
            "turn": "white" if manager.board.turn == chess.WHITE else "black",
            "mode": manager.mode,
            "difficulty": manager.difficulty,
            "calibrated": manager.calibrated,
        }
    return ok("ok", data)


@router.post("/move/detect", response_model=ApiResponse)
async def detect_move_endpoint(
    background_tasks: BackgroundTasks, db=Depends(get_db)
) -> ApiResponse:
    manager = GameManager.get_instance()
    if not manager.calibrated:
        return error("Not calibrated", {"detail": "Run /calibrate first"})

    try:
        curr_state, detections = detect_board_state(manager)
    except Exception as exc:
        return error("Detection failed", {"detail": str(exc)})

    if manager.prev_state is None:
        return error("No previous board state", {"detail": "Run /calibrate again"})

    move, best_score, second_best = detect_move(
        manager.prev_state,
        curr_state,
        manager.board,
        manager.recognizer,
        manager.settings,
    )

    if move is None:
        return error(
            "No legal move matched",
            {"score": best_score, "second_best": second_best, "detections": detections},
        )

    with manager.state_lock:
        if move not in manager.board.legal_moves:
            return error("Illegal move", {"uci": move.uci()})
        san = manager.board.san(move)
        manager.board.push(move)
        manager.prev_state = curr_state

    if manager.current_game_id:
        game_state, err = await record_move(
            db, manager.current_game_id, move.uci(), manager.get_fen()
        )
        if err:
            return error("Failed to persist move", {"detail": err})
        await ws_manager.send_to_game(
            manager.current_game_id,
            {
                "type": "game.move",
                "data": {
                    "game_id": manager.current_game_id,
                    "uci": move.uci(),
                    "fen": manager.get_fen(),
                    "game_version": game_state.get("game_version"),
                },
            },
        )

    # Trigger AI response when playing against the bot
    if manager.mode == "human_vs_ai" and not manager.board.is_game_over():
        background_tasks.add_task(_trigger_ai_move, db)

    data = {
        "uci": move.uci(),
        "san": san,
        "fen": manager.get_fen(),
        "score": best_score,
        "second_best": second_best,
        "detections": detections,
    }
    return ok("Move detected", data)


@router.post("/move/ai", response_model=ApiResponse)
async def ai_move(payload: MoveAiRequest, db=Depends(get_db)) -> ApiResponse:
    manager = GameManager.get_instance()
    difficulty = payload.difficulty or manager.difficulty
    try:
        move = await asyncio.to_thread(
            get_ai_move, manager.board, manager.engine, difficulty, manager.settings.engine_time
        )
    except Exception as exc:
        return error("Engine failed", {"detail": str(exc)})

    with manager.state_lock:
        if move not in manager.board.legal_moves:
            return error("Engine returned illegal move", {"uci": move.uci()})
        manager.board.push(move)

    if manager.current_game_id:
        game_state, err = await record_move(
            db, manager.current_game_id, move.uci(), manager.get_fen()
        )
        if err:
            return error("Failed to persist move", {"detail": err})
        await ws_manager.send_to_game(
            manager.current_game_id,
            {
                "type": "game.move",
                "data": {
                    "game_id": manager.current_game_id,
                    "uci": move.uci(),
                    "fen": manager.get_fen(),
                    "game_version": game_state.get("game_version"),
                },
            },
        )

    data = {
        "uci": move.uci(),
        "fen": manager.get_fen(),
        "turn": "white" if manager.board.turn == chess.WHITE else "black",
    }
    return ok("AI move", data)


async def _trigger_ai_move(db):
    """Background task to fetch and play an AI move."""
    manager = GameManager.get_instance()
    # Wait a bit to let the user see their move on screen
    await asyncio.sleep(0.5)
    
    if manager.board.is_game_over():
        return

    difficulty = manager.difficulty
    try:
        move = await asyncio.to_thread(
            get_ai_move, manager.board, manager.engine, difficulty, manager.settings.engine_time
        )
    except Exception as e:
        print(f"[ERROR] AI move generation failed: {e}")
        return

    with manager.state_lock:
        if move not in manager.board.legal_moves:
            print(f"[ERROR] AI returned illegal move: {move}")
            return
        manager.board.push(move)

    if manager.current_game_id:
        from backend.services.game_service import record_move
        game_state, err = await record_move(
            db, manager.current_game_id, move.uci(), manager.get_fen()
        )
        if err:
            print(f"[ERROR] Failed to record AI move: {err}")
            return

        from backend.realtime.manager import manager as ws_manager
        await ws_manager.send_to_game(
            manager.current_game_id,
            {
                "type": "game.move",
                "data": {
                    "game_id": manager.current_game_id,
                    "uci": move.uci(),
                    "fen": manager.get_fen(),
                    "game_version": game_state.get("game_version"),
                },
            },
        )


@router.post("/game/move", response_model=ApiResponse)
async def submit_move(payload: GameMoveRequest, background_tasks: BackgroundTasks, db=Depends(get_db)) -> ApiResponse:
    from backend.services.game_service import validate_and_record_move
    game_state, err = await validate_and_record_move(
        db,
        payload.game_id,
        payload.uci,
        expected_version=payload.expected_version,
    )
    if err:
        return error("Move rejected", {"detail": err})

    # Update the Singleton Manager so it's in sync for AI / Physical board
    manager = GameManager.get_instance()
    with manager.state_lock:
        try:
            move = chess.Move.from_uci(payload.uci)
            if move in manager.board.legal_moves:
                manager.board.push(move)
        except Exception:
            pass # Already validated in service

    from backend.realtime.manager import manager as ws_manager
    await ws_manager.send_to_game(
        payload.game_id,
        {
            "type": "game.move",
            "data": {
                "game_id": payload.game_id,
                "uci": payload.uci,
                "fen": game_state.get("current_fen"),
                "game_version": game_state.get("game_version"),
            },
        },
    )

    # Trigger AI move if in AI mode and it's AI's turn
    if manager.mode == "human_vs_ai" and not manager.board.is_game_over():
        background_tasks.add_task(_trigger_ai_move, db)

    return ok("Move accepted", game_state)


@router.get("/game/{game_id}/analysis", response_model=ApiResponse)
async def game_analysis(game_id: str, db=Depends(get_db)) -> ApiResponse:
    """
    Full post-game analysis: replays the game through Stockfish and returns
    per-move evaluations, move tags, and an AI insight summary.
    """
    import asyncio
    from backend.repositories.move_repo import get_all_moves
    from backend.services.engine_service import analyze_position

    # 1. Fetch the game and its moves
    game = await get_game_state(db, game_id)
    game_data, err = game
    if err:
        return error("Game not found", {"detail": err})

    moves_docs = await get_all_moves(db, game_id)
    if not moves_docs:
        return error("No moves recorded for this game")

    # 2. Replay and analyze in a thread (Stockfish engine is synchronous)
    manager = GameManager.get_instance()
    engine = manager.engine
    if engine is None:
        return error("Stockfish engine not available")

    def _run_analysis():
        board = chess.Board()
        analysis_moves = []
        eval_scores = [0]  # starting position eval ≈ 0

        # Evaluate starting position
        start_eval = analyze_position(board, engine, time_limit=0.08)
        eval_scores[0] = start_eval["score_cp"]

        for doc in moves_docs:
            uci_str = doc.get("uci", "")
            try:
                move = chess.Move.from_uci(uci_str)
            except Exception:
                continue

            if move not in board.legal_moves:
                continue

            # Engine's best move BEFORE this move is played
            pre_eval = analyze_position(board, engine, time_limit=0.10)
            best_move_uci = pre_eval.get("best_move")
            best_move_san = None
            if best_move_uci:
                try:
                    best_m = chess.Move.from_uci(best_move_uci)
                    if best_m in board.legal_moves:
                        best_move_san = board.san(best_m)
                except Exception:
                    pass

            # SAN of the played move
            san = board.san(move)
            is_white = board.turn == chess.WHITE

            # Push the move
            board.push(move)

            # Evaluate AFTER the move
            post_eval = analyze_position(board, engine, time_limit=0.10)
            score_after = post_eval["score_cp"]
            eval_scores.append(score_after)

            # Compute centipawn loss from the perspective of the player
            score_before = pre_eval["score_cp"]
            if is_white:
                cp_loss = score_before - score_after
            else:
                cp_loss = score_after - score_before

            # Tag the move
            tag = _tag_move(cp_loss, uci_str, best_move_uci)

            analysis_moves.append({
                "move_number": doc.get("move_number", 0),
                "uci": uci_str,
                "san": san,
                "is_white": is_white,
                "score_before": score_before,
                "score_after": score_after,
                "cp_loss": cp_loss,
                "tag": tag,
                "best_move_uci": best_move_uci,
                "best_move_san": best_move_san,
                "fen_after": board.fen(),
            })

        # Build AI insight for the worst mistake
        worst = None
        for m in analysis_moves:
            if m["tag"] in ("blunder", "mistake", "inaccuracy"):
                if worst is None or m["cp_loss"] > worst["cp_loss"]:
                    worst = m

        ai_insight = None
        if worst:
            side = "White" if worst["is_white"] else "Black"
            ai_insight = {
                "move_number": worst["move_number"],
                "played": worst["san"],
                "suggested": worst.get("best_move_san") or worst.get("best_move_uci", "?"),
                "cp_swing": worst["cp_loss"],
                "summary": (
                    f"{side} played {worst['san']} (move {worst['move_number']}), "
                    f"but the engine preferred {worst.get('best_move_san', worst.get('best_move_uci', '?'))}. "
                    f"This cost approximately {worst['cp_loss'] / 100:.1f} pawns of advantage."
                ),
            }

        return {
            "game_id": game_id,
            "total_moves": len(analysis_moves),
            "moves": analysis_moves,
            "eval_scores": eval_scores,
            "ai_insight": ai_insight,
        }

    try:
        result = await asyncio.get_event_loop().run_in_executor(None, _run_analysis)
    except Exception as exc:
        return error("Analysis failed", {"detail": str(exc)})

    return ok("Analysis complete", result)


def _tag_move(cp_loss: int, played_uci: str, best_uci: str | None) -> str:
    """Classify a move based on centipawn loss."""
    if best_uci and played_uci == best_uci:
        return "best"
    if cp_loss <= -50:
        return "brilliant"
    if cp_loss <= 0:
        return "great"
    if cp_loss <= 20:
        return "good"
    if cp_loss <= 50:
        return "good"
    if cp_loss <= 100:
        return "inaccuracy"
    if cp_loss <= 250:
        return "mistake"
    return "blunder"
@router.post("/game/undo", response_model=ApiResponse)
async def game_undo(db=Depends(get_db)) -> ApiResponse:
    manager = GameManager.get_instance()
    game_id = manager.current_game_id
    if not game_id:
        return error("No active game to undo")

    undo_count = 2 if manager.mode == "human_vs_ai" else 1

    with manager.state_lock:
        if len(manager.board.move_stack) < undo_count:
            return error("Not enough moves to undo")
            
        for _ in range(undo_count):
            manager.board.pop()
            
        new_fen = manager.get_fen()

    from backend.db.collections import MOVES, GAMES
    from bson import ObjectId
    
    game_oid = ObjectId(game_id)
    game = await db[GAMES].find_one({"_id": game_oid})
    if game:
        current_version = game.get("game_version", 0)
        await db[MOVES].delete_many({
            "game_id": game_oid,
            "move_number": {"$gt": current_version - undo_count}
        })
        
        last_move_doc = await db[MOVES].find_one(
            {"game_id": game_oid}, sort=[("move_number", -1)]
        )
        last_move_uci = last_move_doc.get("uci") if last_move_doc else None
        new_version = max(0, current_version - undo_count)
        
        await db[GAMES].update_one(
            {"_id": game_oid},
            {"$set": {
                "current_fen": new_fen,
                "game_version": new_version,
                "last_move": last_move_uci
            }}
        )

    await ws_manager.send_to_game(
        game_id,
        {
            "type": "game.state",
            "data": {
                "game_id": game_id,
                "current_fen": new_fen,
                "game_version": new_version if game else 0,
                "last_move": last_move_uci if game else None,
            },
        },
    )

    return ok("Undo successful", {"fen": new_fen})


@router.post("/game/reset", response_model=ApiResponse)
async def game_reset(db=Depends(get_db)) -> ApiResponse:
    manager = GameManager.get_instance()
    if manager.current_game_id:
        await end_game(db, manager.current_game_id, "reset")
        manager.current_game_id = None
    manager.reset_game(keep_calibration=True)
    data = {
        "fen": manager.get_fen(),
        "calibrated": manager.calibrated,
    }
    return ok("Game reset", data)


@router.websocket("/ws")
async def ws_state(websocket: WebSocket, db=Depends(get_db)) -> None:
    await websocket.accept()
    current_game_id: str | None = None
    device_rooms: set[str] = set()
    try:
        while True:
            message = await websocket.receive_json()
            msg_type = message.get("type")
            if msg_type == "hello":
                game_id = message.get("game_id")
                last_known = message.get("last_known_version")
                if not game_id:
                    await websocket.send_json({"type": "error", "message": "game_id required"})
                    continue

                if current_game_id and current_game_id != game_id:
                    ws_manager.disconnect(current_game_id, websocket)
                current_game_id = game_id
                await ws_manager.connect(game_id, websocket)

                game, err = await get_game_state(db, game_id)
                if err:
                    await websocket.send_json({"type": "error", "message": err})
                    continue

                game_version = int(game.get("game_version", 0))
                if last_known is None or last_known < 0 or last_known > game_version:
                    await websocket.send_json({"type": "game.state", "data": game})
                    continue

                if last_known == game_version:
                    await websocket.send_json(
                        {
                            "type": "game.up_to_date",
                            "data": {"game_id": game_id, "game_version": game_version},
                        }
                    )
                    continue

                moves = await get_moves_since(db, game_id, int(last_known))
                await websocket.send_json(
                    {
                        "type": "game.delta",
                        "data": {
                            "game_id": game_id,
                            "from_version": last_known,
                            "to_version": game_version,
                            "moves": moves,
                        },
                    }
                )
            elif msg_type == "resync":
                game_id = message.get("game_id")
                last_known = message.get("last_known_version", -1)
                if not game_id:
                    await websocket.send_json({"type": "error", "message": "game_id required"})
                    continue

                game, err = await get_game_state(db, game_id)
                if err:
                    await websocket.send_json({"type": "error", "message": err})
                    continue

                game_version = int(game.get("game_version", 0))
                if last_known < 0 or last_known > game_version:
                    await websocket.send_json({"type": "game.state", "data": game})
                    continue

                if last_known == game_version:
                    await websocket.send_json(
                        {
                            "type": "game.up_to_date",
                            "data": {"game_id": game_id, "game_version": game_version},
                        }
                    )
                    continue

                moves = await get_moves_since(db, game_id, int(last_known))
                await websocket.send_json(
                    {
                        "type": "game.delta",
                        "data": {
                            "game_id": game_id,
                            "from_version": last_known,
                            "to_version": game_version,
                            "moves": moves,
                        },
                    }
                )
            elif msg_type == "device.subscribe":
                device_ids = message.get("device_ids", [])
                if not isinstance(device_ids, list):
                    await websocket.send_json(
                        {"type": "error", "message": "device_ids must be a list"}
                    )
                    continue
                for device_id in device_ids:
                    if not isinstance(device_id, str) or not device_id:
                        continue
                    room = f"device:{device_id}"
                    if room not in device_rooms:
                        device_rooms.add(room)
                        await ws_manager.connect(room, websocket)
                await websocket.send_json({"type": "device.subscribed", "data": device_ids})
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json({"type": "error", "message": "Unknown message type"})
            await asyncio.sleep(0)
    except WebSocketDisconnect:
        return
    finally:
        if current_game_id:
            ws_manager.disconnect(current_game_id, websocket)
        for room in list(device_rooms):
            ws_manager.disconnect(room, websocket)
