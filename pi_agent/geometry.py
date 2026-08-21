"""Board geometry: square<->millimetre mapping and gridline path planning.

Ported from ``gantry uno/robochess_laptop/geometry.py``.

Coordinate system (matches firmware):
    Origin (0,0) is the homed corner = the 5cm/5cm corner of the top plate.
    +X and +Y both run away from that corner.
    Units are millimetres, matching the firmware's ``MOVEXY`` command.

The one behavioural change from the laptop original: orientation is no longer a
pair of hand-measured module constants. It is per-instance state, so
auto-calibration can determine it from the detected starting position instead of
someone re-measuring the machine.
"""

from __future__ import annotations

from dataclasses import dataclass

# --- Firmware soft limits (must match robochess_gantry.ino) ------------------
# X has to reach past the board to cover the parking strip; Y only ever needs to
# cover the board itself. These MUST match the firmware's max.x / max.y or any
# move into the strip comes back as ERR RANGE.
MAX_X_MM = 560.0
MAX_Y_MM = 450.0

# --- Playing board -----------------------------------------------------------
ORIGIN_OFFSET_X_MM = 50.0   # gap from home corner to the a-file edge
# Measured 2026-08-20 on the real machine: there is NO 5 cm gap between the
# homed zero and the rank-1 edge on this axis; the board starts at y=0.
ORIGIN_OFFSET_Y_MM = 0.0
SQUARE_SIZE_MM = 50.0
BOARD_SPAN_MM = SQUARE_SIZE_MM * 8          # 400

# --- Captured-piece parking strip -------------------------------------------
# Lives beyond the far edge of the board on +X (the end AWAY from home).
# Layout: COLS run along +X (strip depth, 3 deep), ROWS run along Y and line up
# with the 8 ranks, so a slot sits directly opposite the rank it parks from.
GRAVEYARD_X_START_MM = ORIGIN_OFFSET_X_MM + BOARD_SPAN_MM   # 450
GRAVEYARD_DEPTH_MM = 110.0
GRAVEYARD_COLS = 3
GRAVEYARD_ROWS = 8
GRAVEYARD_CAPACITY = GRAVEYARD_ROWS * GRAVEYARD_COLS

# --- Orientation defaults ----------------------------------------------------
# Files and ranks flip INDEPENDENTLY: this machine's files are reversed but its
# ranks are not, which a single "a1 is at the home corner" flag cannot express.
# These are only the fallback used before calibration runs.
DEFAULT_FILES_REVERSED = True     # file a at high x, file h nearest home
DEFAULT_RANKS_REVERSED = False    # rank 1 at low y, nearest home

# --- Motion tuning -----------------------------------------------------------
# How far off a square centre the magnet travels when routing along the gaps
# between squares. Half a square puts it exactly on the gridline.
LATTICE_OFFSET_MM = SQUARE_SIZE_MM / 2.0

# Park position used after a move: a rapid move, not a limit-switch re-home,
# because re-homing every turn is slow and wears the switches.
PARK_X_MM = 0.0
PARK_Y_MM = 0.0

FILES = "abcdefgh"
RANKS = "12345678"


class GeometryError(ValueError):
    pass


def square_name_to_indices(square: str) -> tuple[int, int]:
    """'e4' -> (file_index 0-7, rank_index 0-7)."""
    s = str(square).strip().lower()
    if len(s) != 2 or s[0] not in FILES or s[1] not in RANKS:
        raise GeometryError("not a chess square: %r" % (square,))
    return ord(s[0]) - ord("a"), ord(s[1]) - ord("1")


def indices_to_square_name(file_index: int, rank_index: int) -> str:
    return FILES[file_index] + RANKS[rank_index]


def _sign(v: float) -> int:
    return (v > 0) - (v < 0)


@dataclass
class BoardGeometry:
    """Square<->mm mapping for one physical board setup.

    ``files_reversed`` / ``ranks_reversed`` come from calibration; everything
    else is fixed by how the machine was built.
    """

    files_reversed: bool = DEFAULT_FILES_REVERSED
    ranks_reversed: bool = DEFAULT_RANKS_REVERSED
    origin_offset_x_mm: float = ORIGIN_OFFSET_X_MM
    origin_offset_y_mm: float = ORIGIN_OFFSET_Y_MM
    square_size_mm: float = SQUARE_SIZE_MM
    max_x_mm: float = MAX_X_MM
    max_y_mm: float = MAX_Y_MM

    # -- square <-> millimetre ------------------------------------------------

    def square_to_mm(self, square: str) -> tuple[float, float]:
        """Centre of a chess square, in gantry millimetres."""
        f, r = square_name_to_indices(square)
        if self.files_reversed:
            f = 7 - f
        if self.ranks_reversed:
            r = 7 - r
        x = self.origin_offset_x_mm + (f + 0.5) * self.square_size_mm
        y = self.origin_offset_y_mm + (r + 0.5) * self.square_size_mm
        return (x, y)

    def mm_to_square(self, x: float, y: float) -> str | None:
        """Inverse of :meth:`square_to_mm`. None if (x, y) is off the board."""
        f = int((x - self.origin_offset_x_mm) // self.square_size_mm)
        r = int((y - self.origin_offset_y_mm) // self.square_size_mm)
        if not (0 <= f <= 7 and 0 <= r <= 7):
            return None
        if self.files_reversed:
            f = 7 - f
        if self.ranks_reversed:
            r = 7 - r
        return indices_to_square_name(f, r)

    def graveyard_slot_mm(self, index: int) -> tuple[float, float]:
        """Centre of parking slot ``index`` (0..23) in the capture strip."""
        if not 0 <= index < GRAVEYARD_CAPACITY:
            raise GeometryError("graveyard slot out of range: %r" % (index,))
        # Fill the column nearest the board first (all 8 ranks), then step
        # deeper into the strip. Keeps early captures on the shortest trip.
        col, row = divmod(index, GRAVEYARD_ROWS)
        col_pitch = GRAVEYARD_DEPTH_MM / GRAVEYARD_COLS
        x = GRAVEYARD_X_START_MM + (col + 0.5) * col_pitch
        y = self.origin_offset_y_mm + (row + 0.5) * self.square_size_mm
        return (x, y)

    # -- limits ---------------------------------------------------------------

    def within_limits(self, x: float, y: float, margin: float = 0.0) -> bool:
        return (0.0 - 1e-9) <= x <= (self.max_x_mm - margin + 1e-9) and \
               (0.0 - 1e-9) <= y <= (self.max_y_mm - margin + 1e-9)

    def clamp(self, x: float, y: float) -> tuple[float, float]:
        return (min(max(x, 0.0), self.max_x_mm), min(max(y, 0.0), self.max_y_mm))

    # -- path planning --------------------------------------------------------
    #
    # A piece dragged straight from centre to centre will bulldoze anything
    # standing between the two squares. Rooks/bishops/queens/kings only ever
    # traverse squares that are (by the rules) empty, so those can go direct.
    # Knights and trips to the parking strip cannot, so they are routed along
    # the gaps between squares -- offset half a square onto a gridline, run the
    # long leg there, then step into the destination.

    def plan_board_path(self, from_sq: str, to_sq: str) -> list[tuple[float, float]]:
        """Waypoints (excluding the start point) for dragging a piece between
        two squares. Always ends at the centre of ``to_sq``."""
        ff, fr = square_name_to_indices(from_sq)
        tf, tr = square_name_to_indices(to_sq)
        dfile, drank = tf - ff, tr - fr

        if dfile == 0 and drank == 0:
            return [self.square_to_mm(to_sq)]

        straight = (dfile == 0 or drank == 0)
        diagonal = (abs(dfile) == abs(drank))
        if straight or diagonal:
            # The intervening squares are guaranteed empty for a legal move.
            return [self.square_to_mm(to_sq)]

        # Knight (or any other offset move): travel on the gridlines.
        fx, fy = self.square_to_mm(from_sq)
        tx, ty = self.square_to_mm(to_sq)
        # Take the sidestep direction from the MILLIMETRE delta, not the file or
        # rank index delta. With files_reversed a rising file index means a
        # falling x, so an index-derived sign sidesteps the wrong way and routes
        # the piece across an occupied square instead of along the gap.
        if abs(dfile) < abs(drank):
            # Short leg is X: slide half a square in X onto the file gridline,
            # run the full Y distance there, then step into the target centre.
            gx = fx + _sign(tx - fx) * LATTICE_OFFSET_MM
            return [(gx, fy), (gx, ty), (tx, ty)]
        gy = fy + _sign(ty - fy) * LATTICE_OFFSET_MM
        return [(fx, gy), (tx, gy), (tx, ty)]

    def plan_graveyard_path(self, from_sq: str,
                            slot_xy: tuple[float, float]) -> list[tuple[float, float]]:
        """Waypoints for dragging a captured piece off its square into the
        parking strip on the +X side.

        Step sideways onto the gridline between two ranks, run the whole way out
        along +X on that line (so it passes between rows of pieces rather than
        through them), and only once clear of the board move along Y to the
        slot -- the strip itself is empty, so that last leg is always safe.
        """
        fx, fy = self.square_to_mm(from_sq)
        board_mid_y = self.origin_offset_y_mm + BOARD_SPAN_MM / 2.0
        gy = fy - LATTICE_OFFSET_MM if fy > board_mid_y else fy + LATTICE_OFFSET_MM
        sx, sy = slot_xy
        return [(fx, gy), (sx, gy), (sx, sy)]

    def describe(self) -> str:
        """Human-readable dump of the derived geometry, for the README/UI."""
        return "\n".join([
            "travel envelope      : 0..%.0f mm X, 0..%.0f mm Y" % (self.max_x_mm, self.max_y_mm),
            "board origin offset  : %.0f, %.0f mm" % (self.origin_offset_x_mm, self.origin_offset_y_mm),
            "square size          : %.0f mm (board span %.0f mm)" % (self.square_size_mm, BOARD_SPAN_MM),
            "orientation          : files_reversed=%s ranks_reversed=%s"
            % (self.files_reversed, self.ranks_reversed),
            "a1 centre            : %.1f, %.1f mm" % self.square_to_mm("a1"),
            "h8 centre            : %.1f, %.1f mm" % self.square_to_mm("h8"),
            "parking strip (+X)   : x %.0f..%.0f mm, %d deep x %d ranks = %d slots"
            % (GRAVEYARD_X_START_MM, GRAVEYARD_X_START_MM + GRAVEYARD_DEPTH_MM,
               GRAVEYARD_COLS, GRAVEYARD_ROWS, GRAVEYARD_CAPACITY),
        ])


if __name__ == "__main__":
    print(BoardGeometry().describe())
