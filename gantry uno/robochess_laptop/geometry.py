"""
RoboChess - board geometry, square<->mm mapping, and gridline path planning.

Coordinate system (matches firmware):
    Origin (0,0) is the homed corner = the 5cm/5cm corner of the top plate.
    +X and +Y both run away from that corner.
    Units are millimetres, matching the firmware's MOVEXY command.

Physical layout (parking strip location corrected 2026-08-20):
    60x60 cm top plate, 40x40 cm playing board centred with an asymmetric
    offset: 5 cm frame on the two sides adjacent to home, 15 cm on the other
    two. The captured-piece parking strip is on the +X side - the far end of
    the X axis, i.e. the opposite end from the home corner. The 15 cm gap on
    the +Y side is unused frame.

!! Orientation and the Y origin below are MEASURED from the real machine.
!! The rest (square size, X origin, parking strip depth) is still calculated
!! from stated dimensions - see README "Calibration".
"""

# --- Firmware soft limits (must match robochess_gantry.ino) ------------------
# X has to reach past the board to cover the parking strip; Y only ever needs
# to cover the board itself. These MUST match the firmware's max.x / max.y or
# any move into the strip comes back as ERR RANGE.
MAX_X_MM = 560.0
MAX_Y_MM = 450.0

# --- Playing board -----------------------------------------------------------
ORIGIN_OFFSET_X_MM = 50.0   # gap from home corner to the a-file edge
# Measured 2026-08-20: commanding a7 drove the gantry onto the square
# physically holding h8. The rank being one square high (7 -> 8) means there
# is NO 5 cm gap between the homed zero and the rank-1 edge on this axis -
# the board starts effectively at y=0. The X gap is unchanged.
ORIGIN_OFFSET_Y_MM = 0.0    # gap from home corner to the rank-1 edge
SQUARE_SIZE_MM = 50.0
BOARD_SPAN_MM = SQUARE_SIZE_MM * 8          # 400

# --- Captured-piece parking strip -------------------------------------------
# Lives beyond the far edge of the board on +X (the end AWAY from home),
# inside the 15 cm frame side. Usable depth is 110 mm along X (see README -
# the 15 cm structural offset vs 11 cm usable depth is still unconfirmed).
#
# Layout: COLS run along +X (strip depth, 3 deep), ROWS run along Y and line
# up with the 8 ranks, so a slot sits directly opposite the rank it parks from.
GRAVEYARD_X_START_MM = ORIGIN_OFFSET_X_MM + BOARD_SPAN_MM   # 450
GRAVEYARD_DEPTH_MM = 110.0
GRAVEYARD_COLS = 3    # along +X, into the strip
GRAVEYARD_ROWS = 8    # along Y, one per rank

# --- Orientation -------------------------------------------------------------
# Files and ranks are flipped INDEPENDENTLY. The old single "a1 is at the home
# corner" flag could only mirror both at once, which cannot express this
# machine: its files are reversed but its ranks are not.
#
# Determined from real hardware (see ORIGIN_OFFSET_Y_MM above): a7 landed on
# h8, so file a is at HIGH x - the far end, next to the parking strip - while
# rank 1 stays at LOW y, nearest home.
FILES_REVERSED = True     # file a at high x, file h nearest home
RANKS_REVERSED = False    # rank 1 at low y, nearest home

# --- Motion tuning -----------------------------------------------------------
# How far off a square centre the magnet travels when routing along the gaps
# between squares. Half a square puts it exactly on the gridline.
LATTICE_OFFSET_MM = SQUARE_SIZE_MM / 2.0

# Park position used for "return home" after a move (a rapid move, not a
# limit-switch re-home; re-homing every turn is slow and wears the switches).
PARK_X_MM = 0.0
PARK_Y_MM = 0.0


class GeometryError(ValueError):
    pass


# ---------------------------------------------------------------------------
# Square <-> millimetre
# ---------------------------------------------------------------------------

def square_name_to_indices(square):
    """'e4' -> (file_index 0-7, rank_index 0-7)."""
    s = str(square).strip().lower()
    if len(s) != 2 or s[0] not in "abcdefgh" or s[1] not in "12345678":
        raise GeometryError("not a chess square: %r" % (square,))
    return ord(s[0]) - ord("a"), ord(s[1]) - ord("1")


def indices_to_square_name(file_index, rank_index):
    return "abcdefgh"[file_index] + "12345678"[rank_index]


def square_to_mm(square):
    """Centre of a chess square, in gantry millimetres."""
    f, r = square_name_to_indices(square)
    if FILES_REVERSED:
        f = 7 - f
    if RANKS_REVERSED:
        r = 7 - r
    x = ORIGIN_OFFSET_X_MM + (f + 0.5) * SQUARE_SIZE_MM
    y = ORIGIN_OFFSET_Y_MM + (r + 0.5) * SQUARE_SIZE_MM
    return (x, y)


def mm_to_square(x, y):
    """Inverse of square_to_mm. Returns None if (x,y) is off the board."""
    f = int((x - ORIGIN_OFFSET_X_MM) // SQUARE_SIZE_MM)
    r = int((y - ORIGIN_OFFSET_Y_MM) // SQUARE_SIZE_MM)
    if not (0 <= f <= 7 and 0 <= r <= 7):
        return None
    if FILES_REVERSED:
        f = 7 - f
    if RANKS_REVERSED:
        r = 7 - r
    return indices_to_square_name(f, r)


def graveyard_slot_mm(index):
    """Centre of parking slot `index` (0..23) in the capture strip."""
    if not 0 <= index < GRAVEYARD_ROWS * GRAVEYARD_COLS:
        raise GeometryError("graveyard slot out of range: %r" % (index,))
    # Fill the column nearest the board first (all 8 ranks), then step
    # deeper into the strip. Keeps early captures on the shortest trip.
    col, row = divmod(index, GRAVEYARD_ROWS)
    col_pitch = GRAVEYARD_DEPTH_MM / GRAVEYARD_COLS
    x = GRAVEYARD_X_START_MM + (col + 0.5) * col_pitch
    y = ORIGIN_OFFSET_Y_MM + (row + 0.5) * SQUARE_SIZE_MM
    return (x, y)


GRAVEYARD_CAPACITY = GRAVEYARD_ROWS * GRAVEYARD_COLS


def within_limits(x, y, margin=0.0):
    return (0.0 - 1e-9) <= x <= (MAX_X_MM - margin + 1e-9) and \
           (0.0 - 1e-9) <= y <= (MAX_Y_MM - margin + 1e-9)


def clamp(x, y):
    return (min(max(x, 0.0), MAX_X_MM), min(max(y, 0.0), MAX_Y_MM))


# ---------------------------------------------------------------------------
# Path planning
#
# A piece dragged straight from centre to centre will bulldoze anything
# standing between the two squares. Rooks/bishops/queens/kings only ever
# traverse squares that are (by the rules) empty, so those can go direct.
# Knights and trips to the parking strip cannot, so they are routed along the
# gaps between squares - offset half a square onto a gridline, run the long
# leg there, then step into the destination.
# ---------------------------------------------------------------------------

def _sign(v):
    return (v > 0) - (v < 0)


def plan_board_path(from_sq, to_sq):
    """
    Waypoints (excluding the start point) for dragging a piece from one
    square to another. Always ends at the centre of `to_sq`.
    """
    ff, fr = square_name_to_indices(from_sq)
    tf, tr = square_name_to_indices(to_sq)
    dfile, drank = tf - ff, tr - fr

    if dfile == 0 and drank == 0:
        return [square_to_mm(to_sq)]

    straight = (dfile == 0 or drank == 0)
    diagonal = (abs(dfile) == abs(drank))
    if straight or diagonal:
        # The intervening squares are guaranteed empty for a legal move.
        return [square_to_mm(to_sq)]

    # Knight (or any other offset move): travel on the gridlines.
    fx, fy = square_to_mm(from_sq)
    tx, ty = square_to_mm(to_sq)
    # Take the sidestep direction from the MILLIMETRE delta, not the file or
    # rank index delta. With FILES_REVERSED a rising file index means a
    # falling x, so an index-derived sign sidesteps the wrong way and routes
    # the piece across an occupied square instead of along the gap.
    if abs(dfile) < abs(drank):
        # Short leg is X: slide half a square in X onto the file gridline,
        # run the full Y distance there, then step into the target centre.
        gx = fx + _sign(tx - fx) * LATTICE_OFFSET_MM
        return [(gx, fy), (gx, ty), (tx, ty)]
    else:
        gy = fy + _sign(ty - fy) * LATTICE_OFFSET_MM
        return [(fx, gy), (tx, gy), (tx, ty)]


def plan_graveyard_path(from_sq, slot_xy):
    """
    Waypoints for dragging a captured piece off its square and into the
    parking strip on the +X side.

    Step sideways onto the gridline between two ranks, run the whole way out
    along +X on that line (so it passes between rows of pieces rather than
    through them), and only once clear of the board move along Y to the slot -
    the strip itself is empty, so that last leg is always safe.
    """
    fx, fy = square_to_mm(from_sq)
    # Offset onto the nearest rank gridline, picking the direction that keeps
    # us comfortably inside the Y travel envelope.
    board_mid_y = ORIGIN_OFFSET_Y_MM + BOARD_SPAN_MM / 2.0
    gy = fy - LATTICE_OFFSET_MM if fy > board_mid_y else fy + LATTICE_OFFSET_MM
    sx, sy = slot_xy
    return [(fx, gy), (sx, gy), (sx, sy)]


def describe():
    """Human-readable dump of the derived geometry, for the README/UI."""
    lines = [
        "travel envelope      : 0..%.0f mm X, 0..%.0f mm Y" % (MAX_X_MM, MAX_Y_MM),
        "board origin offset  : %.0f, %.0f mm" % (ORIGIN_OFFSET_X_MM, ORIGIN_OFFSET_Y_MM),
        "square size          : %.0f mm (board span %.0f mm)" % (SQUARE_SIZE_MM, BOARD_SPAN_MM),
        "a1 centre            : %.1f, %.1f mm" % square_to_mm("a1"),
        "h8 centre            : %.1f, %.1f mm" % square_to_mm("h8"),
        "parking strip (+X)   : x %.0f..%.0f mm, %d deep x %d ranks = %d slots"
        % (GRAVEYARD_X_START_MM, GRAVEYARD_X_START_MM + GRAVEYARD_DEPTH_MM,
           GRAVEYARD_COLS, GRAVEYARD_ROWS, GRAVEYARD_CAPACITY),
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    print(describe())
