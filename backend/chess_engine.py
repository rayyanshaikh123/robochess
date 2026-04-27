import cv2
import numpy as np
import chess
import chess.engine
import os
import shutil
import sys
from pathlib import Path

# ================= CONFIG =================
ROOT = Path(__file__).parent.resolve()
STOCKFISH_PATH = str(ROOT / "stockfish" / "stockfish-windows-x86-64-avx2.exe")

SQUARE_SIZE = 80
BOARD_SIZE  = SQUARE_SIZE * 8

EMPTY_REF_PATH           = "empty_board_ref.npy"
OCCUPANCY_DIFF_THRESHOLD = 18.0
OCCUPANCY_STABLE_FRAMES  = 4
MAX_CHANGED_FOR_MOVE     = 6
GRID_SMOOTH_FRAMES       = 3
SQUARE_EMA_ALPHA         = 0.05
OCCUPIED_SCORE_MULT      = 2.2
MIN_OCCUPIED_SCORE       = 6.0

CAMERA_WIDTH             = 640
CAMERA_HEIGHT            = 480
MAX_CAMERA_READ_FAILURES = 60

HAND_SKIN_MOTION_THRESHOLD = 0.004
HAND_MIN_BLOB_RATIO        = 0.0025
HAND_CONFIRM_FRAMES        = 2
HAND_COOLDOWN_FRAMES       = 10

USE_MANUAL_CORNERS     = True
BOARD_RECALC_INTERVAL  = 60
BOARD_MIN_AREA_RATIO   = 0.08
BOARD_ASPECT_TOLERANCE = 0.35

SHOW_PIECE_OVERLAY = True
VERBOSE_STATUS     = False

# ================= INIT =================
def resolve_stockfish(path):
    if os.path.isfile(path): return path
    return shutil.which(path)

stockfish_exe = resolve_stockfish(STOCKFISH_PATH)
if not stockfish_exe:
    print("[ERROR] Stockfish not found.")
    sys.exit(1)

print("[INIT] Loading Stockfish engine...")
try:
    engine = chess.engine.SimpleEngine.popen_uci(stockfish_exe)
    print(f"[OK] Stockfish engine loaded: {stockfish_exe}")
except Exception as e:
    print(f"[ERROR] Stockfish failed: {e}")
    sys.exit(1)

board = chess.Board()
print(f"[OK] Chess board initialized (White to play)")
print(f"[OK] You play as WHITE, Engine plays as BLACK\n")

camera_backend = cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY
cap = cv2.VideoCapture(0, camera_backend)
cap.set(cv2.CAP_PROP_FRAME_WIDTH,  CAMERA_WIDTH)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

if not cap.isOpened():
    print("[WARN] Camera could not be opened. Proceeding without camera...")
    print("       You can still use the debug mode or replay games.")

# ================= GLOBALS =================
empty_board_ref         = None
# KEY FIX: prev_grid is now only updated AFTER a confirmed stable state
# It is NOT overwritten every frame — only on confirmed move or explicit resync
prev_grid               = None
curr_grid               = None
occupancy_diff_buffer   = []
grid_history            = []
cached_warp_matrix      = None
manual_warp_matrix      = None
manual_corner_points    = []
mouse_callback_set      = False
frame_count             = 0
camera_read_fail_streak = 0
prev_hand_gray          = None
hand_present_streak     = 0
hand_cooldown           = 0
square_empty_ema        = {}

# Console state — only print when something actually changes
_last_status_line       = ""
_last_occupied_count    = -1
_awaiting_move          = False   # True once we've locked a pre-move snapshot
_last_tracking_phase    = ""
_engine_move_cooldown   = 0       # Frames to wait after engine move before locking next snapshot
move_history            = []

# ================= HELPERS =================

def order_points(pts):
    rect    = np.zeros((4, 2), dtype="float32")
    s       = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff    = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def on_mouse_click(event, x, y, flags, param):
    global manual_corner_points, manual_warp_matrix, cached_warp_matrix
    if not USE_MANUAL_CORNERS:
        return
    if event == cv2.EVENT_LBUTTONDOWN and len(manual_corner_points) < 4:
        manual_corner_points.append((x, y))
        print(f"  Corner {len(manual_corner_points)}/4 at ({x}, {y})")
        if len(manual_corner_points) == 4:
            pts  = np.array(manual_corner_points, dtype="float32")
            rect = order_points(pts)
            dst  = np.array([[0,0],[BOARD_SIZE-1,0],
                              [BOARD_SIZE-1,BOARD_SIZE-1],[0,BOARD_SIZE-1]], dtype="float32")
            manual_warp_matrix = cv2.getPerspectiveTransform(rect, dst)
            cached_warp_matrix = manual_warp_matrix
            print("[OK] Board corners locked.")


def perspective_transform(frame, force_recalc=False):
    global cached_warp_matrix
    if manual_warp_matrix is not None:
        return cv2.warpPerspective(frame, manual_warp_matrix, (BOARD_SIZE, BOARD_SIZE)), True
    if cached_warp_matrix is not None and not force_recalc:
        return cv2.warpPerspective(frame, cached_warp_matrix, (BOARD_SIZE, BOARD_SIZE)), True

    gray    = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    edges   = cv2.Canny(cv2.GaussianBlur(gray, (5,5), 0), 50, 150)
    cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cnts    = sorted(cnts, key=cv2.contourArea, reverse=True)
    fa      = frame.shape[0] * frame.shape[1]
    best_pts, best_score = None, -1.0

    for cnt in cnts:
        area = cv2.contourArea(cnt)
        if area < fa * BOARD_MIN_AREA_RATIO: break
        approx = cv2.approxPolyDP(cnt, 0.02 * cv2.arcLength(cnt, True), True)
        if len(approx) != 4: continue
        c    = order_points(approx.reshape(4, 2))
        avgw = max(1.0, (np.linalg.norm(c[1]-c[0]) + np.linalg.norm(c[2]-c[3])) / 2)
        avgh = max(1.0, (np.linalg.norm(c[3]-c[0]) + np.linalg.norm(c[2]-c[1])) / 2)
        asp  = avgw / avgh
        if not (1 - BOARD_ASPECT_TOLERANCE <= asp <= 1 + BOARD_ASPECT_TOLERANCE): continue
        if area > fa * 0.95: continue
        score = area * (1.0 - abs(1.0 - asp))
        if score > best_score: best_score, best_pts = score, c

    if best_pts is None:
        if cached_warp_matrix is not None:
            return cv2.warpPerspective(frame, cached_warp_matrix, (BOARD_SIZE, BOARD_SIZE)), True
        return cv2.resize(frame, (BOARD_SIZE, BOARD_SIZE)), False

    dst = np.array([[0,0],[BOARD_SIZE-1,0],[BOARD_SIZE-1,BOARD_SIZE-1],[0,BOARD_SIZE-1]], dtype="float32")
    cached_warp_matrix = cv2.getPerspectiveTransform(best_pts, dst)
    return cv2.warpPerspective(frame, cached_warp_matrix, (BOARD_SIZE, BOARD_SIZE)), True


def map_to_square(x, y, fw=BOARD_SIZE, fh=BOARD_SIZE):
    file = max(0, min(7, int(x / (fw / 8))))
    rank = max(0, min(7, int(y / (fh / 8))))
    return chr(ord('a') + file) + str(8 - rank)


def draw_square_overlay(frame):
    h, w = frame.shape[:2]
    sh, sw = h // 8, w // 8
    for i in range(9):
        cv2.line(frame, (i*sw, 0), (i*sw, h), (60,60,60), 1)
        cv2.line(frame, (0, i*sh), (w, i*sh), (60,60,60), 1)
    for r in range(8):
        for f in range(8):
            cx, cy = int((f+.5)*sw), int((r+.5)*sh)
            cv2.putText(frame, map_to_square(cx,cy,w,h), (cx-12, cy+5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.28, (40,110,200), 1)


def draw_piece_overlay(frame, board_state):
    h, w = frame.shape[:2]
    sh, sw = h//8, w//8
    for sq in chess.SQUARES:
        p = board_state.piece_at(sq)
        if p is None: continue
        n = chess.square_name(sq)
        cx = int((ord(n[0])-ord('a')+.5)*sw)
        cy = int((8-int(n[1])+.5)*sh)
        color = (40,200,40) if p.color == chess.WHITE else (200,200,255)
        cv2.putText(frame, p.symbol(), (cx-6, cy+14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)


# ================= EMPTY REF =================

def capture_empty_ref(warped):
    global empty_board_ref, square_empty_ema
    gray = cv2.GaussianBlur(cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY), (5,5), 0)
    empty_board_ref = gray.copy()
    np.save(EMPTY_REF_PATH, empty_board_ref)
    square_empty_ema.clear()
    print("[OK] Empty reference saved.")


def load_empty_ref():
    global empty_board_ref
    if os.path.exists(EMPTY_REF_PATH):
        empty_board_ref = np.load(EMPTY_REF_PATH)
        print("[OK] Empty reference loaded.")


# ================= OCCUPANCY =================

def _roi(gray, rank, file):
    h, w = gray.shape
    sh, sw = h//8, w//8
    y0, x0 = rank*sh, file*sw
    my, mx = max(2, int(sh*.22)), max(2, int(sw*.22))
    return gray[y0+my:y0+sh-my, x0+mx:x0+sw-mx]


def _score(roi, ref_roi):
    if roi.size == 0 or ref_roi.shape != roi.shape: return 0.0
    intensity = float(np.mean(cv2.absdiff(roi, ref_roi)))
    gradient  = float(np.mean(np.abs(
        cv2.Laplacian(roi, cv2.CV_32F) - cv2.Laplacian(ref_roi, cv2.CV_32F)
    )))
    edge_d    = abs(float(np.mean(cv2.Canny(roi,30,100)))
                  - float(np.mean(cv2.Canny(ref_roi,30,100))))
    return 0.40*intensity + 0.40*gradient + 0.20*edge_d


def get_occupancy_grid(warped, board_state):
    global square_empty_ema, prev_grid

    gray = cv2.GaussianBlur(cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY), (5,5), 0)
    if empty_board_ref is not None and empty_board_ref.shape == gray.shape:
        scale = (float(np.mean(empty_board_ref))+1e-6) / (float(np.mean(gray))+1e-6)
        gray  = np.clip(gray.astype(np.float32)*scale, 0, 255).astype(np.uint8)

    h, w = gray.shape
    grid = {}

    for rank in range(8):
        for file in range(8):
            sq = map_to_square(file*(w//8)+(w//8)/2, rank*(h//8)+(h//8)/2, w, h)
            roi = _roi(gray, rank, file)

            if empty_board_ref is not None and empty_board_ref.shape == gray.shape:
                sc = _score(roi, _roi(empty_board_ref, rank, file))
            else:
                sc = float(np.std(roi)) * 0.5

            try:
                has_piece = board_state.piece_at(chess.parse_square(sq)) is not None
            except Exception:
                has_piece = False

            if not has_piece:
                prev_ema = square_empty_ema.get(sq)
                square_empty_ema[sq] = sc if prev_ema is None else \
                    (1-SQUARE_EMA_ALPHA)*prev_ema + SQUARE_EMA_ALPHA*sc

            ema = square_empty_ema.get(sq)
            threshold = max(MIN_OCCUPIED_SCORE, ema * OCCUPIED_SCORE_MULT) \
                if ema is not None else OCCUPANCY_DIFF_THRESHOLD

            # Hysteresis
            if prev_grid is not None and sq in prev_grid:
                threshold *= 0.80 if prev_grid[sq] else 1.05

            grid[sq] = sc > threshold

    return grid


def smooth_grid(curr):
    global grid_history
    grid_history.append(curr)
    if len(grid_history) > GRID_SMOOTH_FRAMES: grid_history.pop(0)
    if len(grid_history) < GRID_SMOOTH_FRAMES: return curr
    maj = (GRID_SMOOTH_FRAMES // 2) + 1
    return {sq: sum(1 for g in grid_history if g.get(sq,False)) >= maj for sq in curr}


def draw_occupancy_overlay(frame, grid, board_state):
    h, w = frame.shape[:2]
    sh, sw = h//8, w//8
    exp = {chess.square_name(sq): board_state.piece_at(sq) is not None
           for sq in chess.SQUARES}
    for sq, occ in grid.items():
        fi = ord(sq[0])-ord('a')
        ri = 8-int(sq[1])
        x0, y0 = fi*sw, ri*sh
        e = exp.get(sq, False)
        if   occ and e:      color, alpha = (0,220,0),   0.15
        elif occ and not e:  color, alpha = (0,0,255),   0.28
        elif not occ and e:  color, alpha = (255,80,0),  0.28
        else: continue
        ov = frame.copy()
        cv2.rectangle(ov, (x0+1,y0+1), (x0+sw-1,y0+sh-1), color, -1)
        cv2.addWeighted(ov, alpha, frame, 1-alpha, 0, frame)


def infer_move(prev_g, curr_g, board_state):
    vacated = {sq for sq in prev_g if prev_g[sq]    and not curr_g.get(sq,True)}
    landed  = {sq for sq in curr_g if curr_g[sq]    and not prev_g.get(sq,False)}
    best, best_sc = None, -1
    for mv in board_state.legal_moves:
        fr = chess.square_name(mv.from_square)
        to = chess.square_name(mv.to_square)
        sc = 0
        if fr in vacated: sc += 2
        if to in landed:  sc += 2
        if board_state.is_castling(mv)   and fr in vacated: sc += 1
        if board_state.is_en_passant(mv):
            cap = chess.square_name(chess.square(mv.to_square%8, mv.from_square//8))
            if cap in vacated: sc += 1
        if sc > best_sc: best_sc, best = sc, mv
    return best if best_sc >= 2 else None


# ================= HAND DETECTION =================

def is_hand_present(frame, prev_gray=None):
    ycrcb = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb)
    hsv   = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    sm    = cv2.bitwise_or(
        cv2.inRange(ycrcb, np.array([0,140,90],dtype=np.uint8),  np.array([255,175,125],dtype=np.uint8)),
        cv2.inRange(hsv,   np.array([0,40,60], dtype=np.uint8),  np.array([20,200,255], dtype=np.uint8))
    )
    k  = np.ones((5,5), np.uint8)
    sm = cv2.morphologyEx(cv2.threshold(cv2.GaussianBlur(sm,(7,7),0),80,255,cv2.THRESH_BINARY)[1],
                          cv2.MORPH_CLOSE, k)
    ba   = frame.shape[0]*frame.shape[1]
    curr = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    smr = blob = 0.0
    if prev_gray is not None:
        _, mm = cv2.threshold(cv2.absdiff(curr, prev_gray), 28, 255, cv2.THRESH_BINARY)
        mm    = cv2.morphologyEx(mm, cv2.MORPH_CLOSE, k)
        smo   = cv2.bitwise_and(mm, sm)
        smr   = cv2.countNonZero(smo) / ba
        cnts, _ = cv2.findContours(smo, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        blob  = max((cv2.contourArea(c) for c in cnts), default=0.0) / ba
    return (smr >= HAND_SKIN_MOTION_THRESHOLD and blob >= HAND_MIN_BLOB_RATIO), max(smr,blob), curr


# ================= CONSOLE HELPERS =================

def print_board_state(b):
    turn  = "White" if b.turn == chess.WHITE else "Black"
    print(f"\n  Board — Move {b.fullmove_number} | {turn} to play")
    print("  " + "-"*33)
    for rank in range(7, -1, -1):
        row = f"  {rank+1} |"
        for file in range(8):
            sq    = chess.square(file, rank)
            piece = b.piece_at(sq)
            row  += f" {piece.symbol() if piece else '.'} |"
        print(row)
    print("  " + "-"*33)
    print("     a   b   c   d   e   f   g   h\n")


def status_line(occ, stable, changed, turn, move_num):
    state = "STABLE" if stable else "moving"
    t     = "White" if turn == chess.WHITE else "Black"
    return f"  occ={occ:2d}  {state}  changed={changed}  turn={t}  move={move_num}"


def set_tracking_phase(phase, message):
    global _last_tracking_phase
    if phase != _last_tracking_phase:
        print(message)
        _last_tracking_phase = phase


def track_move(source, mover_color, san, move, board_state):
    entry = {
        "ply": len(board_state.move_stack),
        "fullmove": board_state.fullmove_number,
        "source": source,
        "side": "White" if mover_color == chess.WHITE else "Black",
        "san": san,
        "uci": move.uci(),
        "fen": board_state.fen(),
    }
    move_history.append(entry)
    print(
        f"[MOVE][{entry['source']}] {entry['side']} {entry['san']} ({entry['uci']}) "
        f"| ply={entry['ply']} fullmove={entry['fullmove']}"
    )


# ================= STARTUP =================
print("\n[Chess Tracker] Hybrid Occupancy Mode")
print("[Keys] E=capture empty | R=reset corners | S=resync | N=new game | D=debug | ESC=quit\n")

if USE_MANUAL_CORNERS:
    print("[Setup] Click 4 corners: TL → TR → BR → BL\n")

load_empty_ref()

# ================= MAIN LOOP =================
try:
    while True:
        frame_count += 1
        ret, frame  = cap.read()

        if not ret or frame is None or frame.size == 0:
            camera_read_fail_streak += 1
            if camera_read_fail_streak >= MAX_CAMERA_READ_FAILURES:
                print("[ERROR] Camera lost.")
                break
            cv2.waitKey(1)
            continue
        camera_read_fail_streak = 0

        if not mouse_callback_set:
            cv2.namedWindow("Chess Tracker")
            cv2.setMouseCallback("Chess Tracker", on_mouse_click)
            mouse_callback_set = True

        # ---- corner calibration ----
        if USE_MANUAL_CORNERS and manual_warp_matrix is None:
            preview = frame.copy()
            for i, pt in enumerate(manual_corner_points):
                cv2.circle(preview, pt, 6, (0,255,255), -1)
                cv2.putText(preview, str(i+1), (pt[0]+8, pt[1]-8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,255,255), 2)
            cv2.putText(preview, "Click: TL  TR  BR  BL",
                        (10,30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,200,255), 2)
            cv2.putText(preview, "R = reset corners",
                        (10,58), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0,200,255), 2)
            cv2.imshow("Chess Tracker", preview)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('r'): manual_corner_points.clear()
            elif key == 27: break
            continue

        # ---- warp ----
        warped, locked = perspective_transform(frame, frame_count % BOARD_RECALC_INTERVAL == 1)
        display        = warped.copy()

        if not locked:
            occupancy_diff_buffer.clear()
            cv2.putText(display, "Board not locked", (10,30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0,0,255), 2)
            cv2.imshow("Chess Tracker", display)
            if cv2.waitKey(1) & 0xFF == 27: break
            continue

        # ---- hand ----
        hand_now, hand_ratio, curr_hand_gray = is_hand_present(warped, prev_hand_gray)
        prev_hand_gray = curr_hand_gray
        if hand_now:           hand_cooldown = HAND_COOLDOWN_FRAMES
        elif hand_cooldown > 0: hand_cooldown -= 1
        hand_present_streak = (hand_present_streak+1) if hand_now else 0
        hand_active = (hand_present_streak >= HAND_CONFIRM_FRAMES) or (hand_cooldown > 0)

        if hand_active:
            occupancy_diff_buffer.clear()
            # Do NOT reset prev_grid here — we want to keep the pre-move snapshot
            set_tracking_phase("HAND", "[TRACK] Hand detected, waiting for clear board view.")
            cv2.putText(display, "HAND DETECTED | WAIT",
                        (10,30), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0,0,255), 2)
            cv2.imshow("Chess Tracker", display)
            if cv2.waitKey(1) & 0xFF == 27: break
            continue

        # ---- draw ----
        draw_square_overlay(display)
        if SHOW_PIECE_OVERLAY:
            draw_piece_overlay(display, board)

        # ---- occupancy ----
        raw       = get_occupancy_grid(warped, board)
        curr_grid = smooth_grid(raw)
        draw_occupancy_overlay(display, curr_grid, board)

        # ---- no ref yet ----
        if empty_board_ref is None:
            cv2.putText(display, "Remove pieces → press E",
                        (10,30), cv2.FONT_HERSHEY_SIMPLEX, 0.60, (0,200,255), 2)
            cv2.imshow("Chess Tracker", display)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('e'): capture_empty_ref(warped)
            elif key == 27: break
            continue

        # ---- stability ----
        occ_snapshot = tuple(sorted(sq for sq, v in curr_grid.items() if v))
        occupancy_diff_buffer.append(occ_snapshot)
        if len(occupancy_diff_buffer) > OCCUPANCY_STABLE_FRAMES:
            occupancy_diff_buffer.pop(0)

        grid_stable = (
            len(occupancy_diff_buffer) == OCCUPANCY_STABLE_FRAMES and
            all(g == occupancy_diff_buffer[0] for g in occupancy_diff_buffer)
        )

        occ_count = len(occ_snapshot)

                # Decrement engine move cooldown each frame
        if _engine_move_cooldown > 0:
            _engine_move_cooldown -= 1

        # -------------------------------------------------------
        # KEY FIX: prev_grid update logic
        #
        # OLD (broken): prev_grid = curr_grid  ← ran every frame,
        #   so by the time the grid re-stabilised after a move,
        #   prev_grid already equalled curr_grid → changed = 0
        #
        # NEW:
        #   - When stable and no pending move: lock prev_grid as
        #     the "before" snapshot (awaiting_move = True)
        #   - Only update prev_grid again after a move fires or
        #     after an explicit resync
        #   - Skip locking during _engine_move_cooldown to allow
        #     the user to physically update board with engine move
        # -------------------------------------------------------
        if grid_stable and not _awaiting_move and _engine_move_cooldown == 0:
            # Lock the current stable state as our "before" reference
            prev_grid = curr_grid.copy()
            _awaiting_move = True
            set_tracking_phase("READY", "[TRACK] Stable snapshot locked. Waiting for move.")

        changed = []
        if prev_grid is not None:
            changed = [sq for sq in curr_grid if curr_grid[sq] != prev_grid.get(sq)]

        if not grid_stable:
            set_tracking_phase("MOVING", "[TRACK] Board is changing...")

        # ---- HUD ----
        sl = status_line(occ_count, grid_stable, len(changed), board.turn, board.fullmove_number)
        if VERBOSE_STATUS and sl != _last_status_line:
            print(sl)
            _last_status_line = sl

        hud_state = "STABLE" if grid_stable else "MOVING"
        hud_turn = "WHITE" if board.turn == chess.WHITE else "BLACK"
        if grid_stable and _awaiting_move:
            hud_track = "AWAIT MOVE"
        elif not grid_stable:
            hud_track = "SCANNING"
        else:
            hud_track = "LOCKING"

        cv2.putText(display,
                    f"{hud_state} | OCC {occ_count} | CHG {len(changed)}",
                    (10,28), cv2.FONT_HERSHEY_SIMPLEX, 0.58,
                    (0,220,0) if grid_stable else (0,140,255), 2)
        cv2.putText(display,
                    f"{hud_turn} | MOVE {board.fullmove_number} | {hud_track}",
                    (10,52), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (200,200,200), 1)

        if _awaiting_move:
            cv2.putText(display, "YOUR MOVE",
                        (10, BOARD_SIZE-12), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (0,200,255), 1)

        # ---- move inference ----
        if (grid_stable and _awaiting_move and prev_grid is not None
                and 1 <= len(changed) <= MAX_CHANGED_FOR_MOVE):

            vacated = [sq for sq in prev_grid if prev_grid[sq] and not curr_grid.get(sq,True)]
            landed  = [sq for sq in curr_grid if curr_grid[sq] and not prev_grid.get(sq,False)]

            if vacated or landed:
                move = infer_move(prev_grid, curr_grid, board)

                if move and move in board.legal_moves:
                    san   = board.san(move)
                    piece = board.piece_at(move.from_square)
                    pname = chess.piece_name(piece.piece_type) if piece else "piece"
                    mover_color = board.turn  # Capture WHITE before pushing

                    print(f"[MOVE] WHITE: {pname} {san} ({move.uci()})")

                    board.push(move)
                    track_move("YOU", mover_color, san, move, board)

                    # Reset — unlock so next stable state becomes new "before"
                    prev_grid      = None
                    _awaiting_move = False
                    set_tracking_phase("POST_MOVE", "[TRACK] Move accepted. Requesting engine response.")
                    occupancy_diff_buffer.clear()
                    grid_history.clear()

                    if board.is_game_over():
                        outcome = board.outcome()
                        print(f"[GAME OVER] {outcome.result()} {outcome.termination.name}\n")
                    else:
                        try:
                            print("[ENGINE] Thinking...")
                            result  = engine.play(board, chess.engine.Limit(time=0.5))
                            eng_san = board.san(result.move)
                            engine_color = board.turn  # Capture BLACK before pushing engine move
                            print(f"[MOVE] BLACK: {eng_san} ({result.move.uci()})")
                            board.push(result.move)
                            track_move("ENGINE", engine_color, eng_san, result.move, board)
                            # After engine plays, cooldown prevents premature snapshot locking
                            # until user physically updates board with engine move (approx 0.5s)
                            _engine_move_cooldown = 15  # ~0.5s at 30fps
                            if board.is_game_over():
                                outcome = board.outcome()
                                print(f"[GAME OVER] {outcome.result()} {outcome.termination.name}\n")
                        except Exception as e:
                            print(f"[ERROR] Engine failed: {e}")

        cv2.imshow("Chess Tracker", display)

        # ---- keys ----
        key = cv2.waitKey(1) & 0xFF
        if key == 27: break

        elif key == ord('r'):
            manual_corner_points.clear()
            manual_warp_matrix = cached_warp_matrix = None
            occupancy_diff_buffer.clear()
            grid_history.clear()
            square_empty_ema.clear()
            prev_grid = None
            _awaiting_move = False
            set_tracking_phase("", "")
            print("\n[Setup] Corners reset — click TL TR BR BL\n")

        elif key == ord('e'):
            capture_empty_ref(warped)
            prev_grid = None
            _awaiting_move = False
            occupancy_diff_buffer.clear()
            grid_history.clear()
            set_tracking_phase("", "")

        elif key == ord('s'):
            prev_grid = None
            _awaiting_move = False
            _engine_move_cooldown = 0
            occupancy_diff_buffer.clear()
            grid_history.clear()
            square_empty_ema.clear()
            set_tracking_phase("", "")
            print("[RESYNC] Done\n")

        elif key == ord('n'):
            board = chess.Board()
            prev_grid = None
            _awaiting_move = False
            _engine_move_cooldown = 0
            occupancy_diff_buffer.clear()
            grid_history.clear()
            square_empty_ema.clear()
            move_history.clear()
            set_tracking_phase("", "")
            print("\n[GAME] New game started\n")

        elif key == ord('d'):
            print(f"\n  [DEBUG] Occupied : {sorted(sq for sq,v in curr_grid.items() if v)}")
            print(f"  [DEBUG] prev_grid: {'set' if prev_grid else 'None'}")
            print(f"  [DEBUG] awaiting : {_awaiting_move}")
            print(f"  [DEBUG] phase    : {_last_tracking_phase or 'None'}")
            print(f"  [DEBUG] changed  : {changed}")
            print(f"  [DEBUG] moves    : {len(move_history)}")
            if changed:
                vacated = [sq for sq in prev_grid if prev_grid.get(sq) and not curr_grid.get(sq,True)]
                landed  = [sq for sq in curr_grid if curr_grid[sq] and not prev_grid.get(sq,False)]
                print(f"  [DEBUG] vacated  : {vacated}")
                print(f"  [DEBUG] landed   : {landed}")
            if move_history:
                print("  [DEBUG] recent   :")
                for m in move_history[-6:]:
                    print(f"    - {m['ply']:>2} {m['source']:<6} {m['side']:<5} {m['san']:<8} {m['uci']}")
            print()

except KeyboardInterrupt:
    print("\n  Interrupted.")

finally:
    cap.release()
    cv2.destroyAllWindows()
    try: engine.quit()
    except Exception: pass
    print("  Shutdown complete.\n")