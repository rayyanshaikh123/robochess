"""Line-oriented text protocol between the Pi and the Arduino Uno gantry.

The firmware (``gantry uno/robochess_gantry/robochess_gantry.ino``) speaks plain
uppercase verbs at 115200 baud, one per line, and answers with lines prefixed
``OK`` (success) or ``ERR`` (failure):

    PING              -> OK PONG <version>
    STATUS            -> OK X=12.50 Y=300.00 HOMED=1 MAG=OFF LIMX=0 LIMY=0
    HOME              -> limit-switch homing, sets (0,0)
    MOVEXY <x> <y>    -> absolute move, millimetres
    JOG <X|Y> <mm>    -> relative move
    MAG <ON|OFF>      -> electromagnet
    STOP              -> abort motion, release the coil

It also prints ``READY RoboChess gantry <version>`` once on boot.

The firmware only accepts absolute millimetres, so square -> mm mapping and
path planning live here on the host (see :mod:`pi_agent.geometry`).
"""

from __future__ import annotations

from dataclasses import dataclass, field
import re
import threading
import time
from typing import Protocol

import chess

from pi_agent.geometry import (
    GRAVEYARD_CAPACITY,
    PARK_X_MM,
    PARK_Y_MM,
    BoardGeometry,
)

BAUD_DEFAULT = 115200

# Ack tokens are matched leniently and case-insensitively: the firmware emits
# OK/ERR, but READY (boot banner) also counts as a positive terminator so a
# reconnect mid-session is not read as a timeout.
ACK_TOKENS_OK = ("OK", "DONE", "READY")
ACK_TOKENS_ERR = ("ERR", "ERROR", "FAIL", "ALARM")

# Motion is blocking in firmware, so the ack only arrives once the carriage has
# stopped. Homing crawls onto both limit switches and needs the most headroom.
TIMEOUT_SHORT_S = 5.0     # PING / STATUS / MAG / STOP
TIMEOUT_MOVE_S = 45.0     # MOVEXY / JOG
TIMEOUT_HOME_S = 90.0     # HOME

# Dwell after switching the coil so the piece is actually held (or released)
# before the carriage starts moving.
MAGNET_SETTLE_S = 0.25

STATUS_RE = re.compile(
    r"X=(-?\d+(?:\.\d+)?)\s+Y=(-?\d+(?:\.\d+)?)"
    r"(?:\s+HOMED=(\d))?(?:\s+MAG=(ON|OFF))?"
    r"(?:\s+LIMX=(\d))?(?:\s+LIMY=(\d))?",
    re.IGNORECASE,
)


class UnoError(RuntimeError):
    pass


@dataclass
class GantryStatus:
    x_mm: float | None = None
    y_mm: float | None = None
    homed: bool | None = None
    magnet_on: bool | None = None
    limit_x: bool | None = None
    limit_y: bool | None = None
    raw: str = ""

    @classmethod
    def parse(cls, lines: list[str]) -> "GantryStatus":
        for line in reversed(lines):
            match = STATUS_RE.search(line)
            if not match:
                continue
            x, y, homed, mag, limx, limy = match.groups()
            return cls(
                x_mm=float(x),
                y_mm=float(y),
                homed=None if homed is None else homed == "1",
                magnet_on=None if mag is None else mag.upper() == "ON",
                limit_x=None if limx is None else limx == "1",
                limit_y=None if limy is None else limy == "1",
                raw=line,
            )
        return cls(raw=lines[-1] if lines else "")

    def as_dict(self) -> dict:
        return {
            "x_mm": self.x_mm,
            "y_mm": self.y_mm,
            "homed": self.homed,
            "magnet_on": self.magnet_on,
            "limit_x": self.limit_x,
            "limit_y": self.limit_y,
            "raw": self.raw,
        }


class TextLineTransport(Protocol):
    def send(self, command: str, timeout: float) -> tuple[bool, list[str]]: ...
    def close(self) -> None: ...


class SerialTransport:
    """pyserial transport that collects reply lines until an ack token."""

    def __init__(self, port: str, baudrate: int = BAUD_DEFAULT,
                 boot_wait: float = 2.0) -> None:
        try:
            import serial
        except ImportError as exc:
            raise UnoError("Install pyserial to use a physical Uno") from exc
        try:
            self._serial = serial.Serial(port, int(baudrate), timeout=0.2,
                                         write_timeout=5)
        except Exception as exc:  # serial.SerialException and friends
            raise UnoError(f"Cannot open Uno on {port}: {exc}") from exc
        self._lock = threading.Lock()
        # Opening the port resets the Uno, which then re-prints its banner and
        # ignores anything sent during the bootloader window.
        time.sleep(max(0.0, boot_wait))
        self._serial.reset_input_buffer()

    def send(self, command: str, timeout: float) -> tuple[bool, list[str]]:
        with self._lock:
            try:
                self._serial.write((command + "\n").encode("ascii", "ignore"))
                self._serial.flush()
            except Exception as exc:
                raise UnoError(f"Uno write failed ({command}): {exc}") from exc

            deadline = time.monotonic() + timeout
            lines: list[str] = []
            buffer = b""
            while time.monotonic() < deadline:
                try:
                    chunk = self._serial.read(256)
                except Exception as exc:
                    raise UnoError(f"Uno read failed ({command}): {exc}") from exc
                if not chunk:
                    continue
                buffer += chunk
                while b"\n" in buffer:
                    raw, buffer = buffer.split(b"\n", 1)
                    line = raw.decode("utf-8", "replace").strip()
                    if not line:
                        continue
                    lines.append(line)
                    upper = line.upper()
                    if upper.startswith(ACK_TOKENS_ERR):
                        return False, lines
                    if upper.startswith(ACK_TOKENS_OK):
                        return True, lines
            return False, lines

    def close(self) -> None:
        try:
            self._serial.close()
        except Exception:
            pass


class SimulatedTransport:
    """In-memory stand-in used by tests and ``ROBOCHESS_UNO_SIMULATOR``."""

    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.commands: list[str] = []

    def send(self, command: str, timeout: float) -> tuple[bool, list[str]]:
        self.commands.append(command)
        if self.fail:
            return False, ["ERR simulated failure"]
        verb = command.split()[0].upper() if command.split() else ""
        if verb == "PING":
            return True, ["OK PONG simulated"]
        if verb in {"STATUS", "MOVEXY", "JOG", "HOME"}:
            return True, ["OK X=0.00 Y=0.00 HOMED=1 MAG=OFF LIMX=0 LIMY=0"]
        return True, ["OK"]

    def close(self) -> None:
        return


@dataclass(frozen=True)
class MotionPlan:
    """High-level physical actions for one chess move.

    Coordinates are resolved to millimetres by :class:`UnoController`, which
    owns the board geometry.
    """

    uci: str
    operations: list[dict]


def motion_plan(board: chess.Board, move: chess.Move) -> MotionPlan:
    if move not in board.legal_moves:
        raise UnoError(f"Cannot plan illegal move {move.uci()}")
    ops: list[dict] = []
    if board.is_en_passant(move):
        captured = chess.square(chess.square_file(move.to_square),
                                chess.square_rank(move.from_square))
        ops.append({"op": "remove", "square": chess.square_name(captured)})
    elif board.is_capture(move):
        ops.append({"op": "remove", "square": chess.square_name(move.to_square)})
    ops.append({"op": "move", "from": chess.square_name(move.from_square),
                "to": chess.square_name(move.to_square)})
    if board.is_castling(move):
        rank = chess.square_rank(move.from_square)
        kingside = chess.square_file(move.to_square) > chess.square_file(move.from_square)
        rook_from = chess.square(7 if kingside else 0, rank)
        rook_to = chess.square(5 if kingside else 3, rank)
        ops.append({"op": "move", "from": chess.square_name(rook_from),
                    "to": chess.square_name(rook_to)})
    if move.promotion:
        ops.append({"op": "promote", "square": chess.square_name(move.to_square),
                    "piece": chess.piece_name(move.promotion)})
    return MotionPlan(move.uci(), ops)


@dataclass
class UnoController:
    """Drives the gantry: resolves plans to millimetres and talks the protocol."""

    transport: TextLineTransport
    timeout: float = TIMEOUT_SHORT_S
    retries: int = 1
    geometry: BoardGeometry = field(default_factory=BoardGeometry)
    #: Squares needing a human hand, e.g. promotion swaps the machine cannot do.
    manual_actions: list[str] = field(default_factory=list)
    _graveyard_used: int = 0

    def ensure_homed(self) -> dict:
        """Verify the Uno has homed before any coordinate motion."""
        status = self.status()
        if status.homed is not True:
            raise UnoError("Gantry is not homed; send gantry.home before moving")
        return status.as_dict()

    # -- protocol primitives --------------------------------------------------

    def command(self, text: str, timeout: float | None = None) -> list[str]:
        """Send one line, retrying, and raise :class:`UnoError` on ERR/timeout."""
        limit = self.timeout if timeout is None else timeout
        last: list[str] = []
        for _ in range(max(1, self.retries + 1)):
            ok, lines = self.transport.send(text, limit)
            if ok:
                return lines
            last = lines
        detail = f": {last[-1]}" if last else ""
        raise UnoError(f"Uno rejected {text!r}{detail}")

    def ping(self) -> bool:
        self.command("PING", TIMEOUT_SHORT_S)
        return True

    def status(self) -> dict:
        return GantryStatus.parse(self.command("STATUS", TIMEOUT_SHORT_S)).as_dict()

    def home(self) -> None:
        self.command("HOME", TIMEOUT_HOME_S)
        status = self.status()
        if status.homed is not True:
            raise UnoError("Uno acknowledged HOME but did not report HOMED=1")

    def stop(self) -> None:
        self.command("STOP", TIMEOUT_SHORT_S)

    def magnet(self, on: bool) -> None:
        self.command(f"MAG {'ON' if on else 'OFF'}", TIMEOUT_SHORT_S)
        time.sleep(MAGNET_SETTLE_S)

    def move_to(self, x: float, y: float) -> None:
        if not self.geometry.within_limits(x, y):
            raise UnoError(f"Target ({x:.1f}, {y:.1f}) mm is outside the travel envelope")
        self.command(f"MOVEXY {x:.2f} {y:.2f}", TIMEOUT_MOVE_S)

    def park(self) -> None:
        self.move_to(PARK_X_MM, PARK_Y_MM)

    # -- plan execution -------------------------------------------------------

    def reset_graveyard(self) -> None:
        """Call when a new game starts; the strip is cleared by hand."""
        self._graveyard_used = 0
        self.manual_actions.clear()

    def execute(self, plan: MotionPlan) -> None:
        """Run a :class:`MotionPlan`, releasing the magnet if anything fails."""
        try:
            self.ensure_homed()
            for op in plan.operations:
                kind = op.get("op")
                if kind == "remove":
                    self._drag_to_graveyard(op["square"])
                elif kind == "move":
                    self._drag(op["from"], op["to"])
                elif kind == "promote":
                    # The machine has no piece reservoir, so the swap is manual.
                    self.manual_actions.append(
                        f"place {op.get('piece', 'queen')} on {op['square']}"
                    )
                else:
                    raise UnoError(f"Unknown motion op {kind!r}")
            self.park()
        except UnoError:
            self._release_quietly()
            raise

    def _drag(self, from_sq: str, to_sq: str) -> None:
        self.move_to(*self.geometry.square_to_mm(from_sq))
        self.magnet(True)
        for x, y in self.geometry.plan_board_path(from_sq, to_sq):
            self.move_to(x, y)
        self.magnet(False)

    def _drag_to_graveyard(self, square: str) -> None:
        if self._graveyard_used >= GRAVEYARD_CAPACITY:
            raise UnoError("Capture strip is full; clear it before continuing")
        slot = self.geometry.graveyard_slot_mm(self._graveyard_used)
        self.move_to(*self.geometry.square_to_mm(square))
        self.magnet(True)
        for x, y in self.geometry.plan_graveyard_path(square, slot):
            self.move_to(x, y)
        self.magnet(False)
        self._graveyard_used += 1

    def _release_quietly(self) -> None:
        """Never leave an energised coil on a halted machine."""
        try:
            self.transport.send("MAG OFF", TIMEOUT_SHORT_S)
        except Exception:
            pass

    def close(self) -> None:
        self.transport.close()
