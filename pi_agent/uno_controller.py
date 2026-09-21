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
import glob
import os
from pathlib import Path
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

# Python-side settle after switching the coil. The firmware already blocks for
# cfg.magDwellMs; this settle guard gives ample time for the magnetic field
# to firmly grip or release the piece before the carriage moves.
def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


MAGNET_SETTLE_S = max(0.0, _env_float("ROBOCHESS_MAGNET_SETTLE_SECONDS", 0.04))
GANTRY_HOME_MODE = os.getenv("ROBOCHESS_GANTRY_HOME_MODE", "never").strip().lower()
if GANTRY_HOME_MODE not in {"always", "interval", "never"}:
    GANTRY_HOME_MODE = "never"
GANTRY_REHOME_INTERVAL = max(1, _env_int("ROBOCHESS_GANTRY_REHOME_INTERVAL", 50))

# Speed profile pushed to the firmware after homing.
# Restores safe, snappy verified speed (80 mm/s / 1000 mm/s² / 100 ms dwell) and
# saves them to EEPROM.
FIRMWARE_MAX_SPEED  = _env_float("ROBOCHESS_FIRMWARE_MAX_SPEED", 80.0)     # mm/s  — brisk, smooth verified speed
FIRMWARE_MAX_ACCEL  = _env_float("ROBOCHESS_FIRMWARE_MAX_ACCEL", 1000.0)   # mm/s² — crisp acceleration; avoids step skipping
FIRMWARE_MAG_DWELL  = _env_int("ROBOCHESS_FIRMWARE_MAG_DWELL", 100)        # ms    — ample dwell for piece pickup/release

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


def find_uno_port(preferred: str = "") -> str | None:
    """Find the serial device for the Arduino Uno.

    Checks in order:
    1. preferred path if given and exists
    2. /dev/serial/by-id/* symlinks
    3. /dev/ttyACM* devices (standard Arduino Uno)
    4. /dev/ttyUSB* devices (CH340/FTDI Arduino clones)
    5. pyserial list_ports enumeration
    """
    if preferred:
        p = Path(preferred)
        if p.exists():
            return str(p)

    by_id = Path("/dev/serial/by-id")
    if by_id.is_dir():
        for item in sorted(by_id.iterdir()):
            target = str(item.resolve())
            if Path(target).exists():
                return target

    for p in sorted(glob.glob("/dev/ttyACM*")):
        if Path(p).exists():
            return p

    for p in sorted(glob.glob("/dev/ttyUSB*")):
        if Path(p).exists():
            return p

    try:
        import serial.tools.list_ports
        ports = list(serial.tools.list_ports.comports())
        for p in ports:
            desc = f"{p.description} {p.manufacturer or ''} {p.hwid}".lower()
            if any(k in desc for k in ["arduino", "ch340", "cp210", "ftdi", "usb serial", "cdc"]):
                return p.device
        if ports:
            return ports[0].device
    except Exception:
        pass

    return None


class TextLineTransport(Protocol):
    def send(self, command: str, timeout: float) -> tuple[bool, list[str]]: ...
    def close(self) -> None: ...


class SerialTransport:
    """pyserial transport that collects reply lines until an ack token."""

    def __init__(self, port: str, baudrate: int = BAUD_DEFAULT,
                 boot_wait: float = 2.0) -> None:
        self.port = str(port)
        self.baudrate = int(baudrate)
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
                if hasattr(self._serial, "reset_input_buffer"):
                    self._serial.reset_input_buffer()
                self._serial.write((command + "\n").encode("ascii", "ignore"))
                self._serial.flush()
            except Exception as exc:
                raise UnoError(f"Uno write failed ({command}): {exc}") from exc

            deadline = time.monotonic() + timeout
            lines: list[str] = []
            buffer = b""
            while time.monotonic() < deadline:
                try:
                    available = getattr(self._serial, "in_waiting", 0)
                    chunk = self._serial.read(available if available > 0 else 1)
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
                        if upper.startswith("OK HOMING"):
                            continue
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
    _magnet_engaged: bool = False
    _homed: bool = False
    home_mode: str = GANTRY_HOME_MODE
    rehome_interval: int = GANTRY_REHOME_INTERVAL
    _moves_since_home: int = 0
    _speed_profile: dict = field(default_factory=dict)

    def ensure_homed(self) -> dict:
        """Verify the Uno has homed before any coordinate motion."""
        if self._homed:
            return {"homed": True}
        try:
            status = self.read_status()
            if status.homed is True:
                self._homed = True
                self._apply_speed_config()
                return status.as_dict()
        except Exception:
            pass
        if self._homed:
            return {"homed": True}
        raise UnoError("Gantry is not homed; send gantry.home before moving")

    def _apply_speed_config(self) -> None:
        """Push the preferred speed profile to firmware and persist it to EEPROM.

        Uses the firmware's SET command, which validates, saves, and applies the
        value immediately.  Failures are logged but not fatal — the machine still
        runs on its existing EEPROM defaults.
        """
        settings = [
            ("max.speed", f"{FIRMWARE_MAX_SPEED:.1f}"),
            ("max.accel", f"{FIRMWARE_MAX_ACCEL:.1f}"),
            ("mag.dwell", str(FIRMWARE_MAG_DWELL)),
        ]
        for key, val in settings:
            try:
                self.command(f"SET {key} {val}", TIMEOUT_SHORT_S)
            except UnoError as exc:
                # Non-fatal: log and continue; defaults are safe.
                import sys
                print(f"[warn] uno_controller: SET {key} {val} failed: {exc}", file=sys.stderr)

    def set_speed(self, *, max_rate_mm_min: float, accel_mm_sec2: float) -> dict:
        """Set a user-facing speed profile and apply it immediately.

        The app uses mm/min while the Uno firmware uses mm/s.
        """
        if max_rate_mm_min <= 0 or accel_mm_sec2 <= 0:
            raise ValueError("Gantry speed and acceleration must be positive")
        if max_rate_mm_min > 12000 or accel_mm_sec2 > 5000:
            raise ValueError("Gantry speed or acceleration exceeds the safe limit")
        max_speed = max_rate_mm_min / 60.0
        self.command(f"SET max.speed {max_speed:.1f}", TIMEOUT_SHORT_S)
        self.command(f"SET max.accel {accel_mm_sec2:.1f}", TIMEOUT_SHORT_S)
        self._speed_profile = {
            "max_rate_mm_min": float(max_rate_mm_min),
            "max_speed_mm_sec": max_speed,
            "max_accel_mm_sec2": float(accel_mm_sec2),
        }
        return self._speed_profile.copy()

    def speed_profile(self) -> dict:
        return self._speed_profile.copy() or {
            "max_rate_mm_min": FIRMWARE_MAX_SPEED * 60.0,
            "max_speed_mm_sec": FIRMWARE_MAX_SPEED,
            "max_accel_mm_sec2": FIRMWARE_MAX_ACCEL,
        }

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

    def read_status(self) -> GantryStatus:
        """Parsed status, for callers that need to inspect fields."""
        return GantryStatus.parse(self.command("STATUS", TIMEOUT_SHORT_S))

    def status(self) -> dict:
        """JSON-friendly status, as surfaced over BLE and the local HTTP API."""
        is_sim = isinstance(self.transport, SimulatedTransport)
        port_name = getattr(self.transport, "port", None)
        try:
            res = self.read_status().as_dict()
            if self._homed:
                res["homed"] = True
            res["simulated"] = is_sim
            res["port"] = port_name
            return res
        except Exception as exc:
            return {
                "homed": self._homed,
                "simulated": is_sim,
                "port": port_name,
                "error": str(exc),
            }

    def reconnect(self, preferred_port: str = "", baudrate: int = BAUD_DEFAULT) -> dict:
        """Attempt to reconnect or switch to physical serial transport."""
        port = find_uno_port(preferred_port)
        if not port:
            return {
                "ok": False,
                "simulated": isinstance(self.transport, SimulatedTransport),
                "message": "No serial port found for Arduino Uno",
            }
        try:
            new_trans = SerialTransport(port, baudrate)
            old_trans = self.transport
            self.transport = new_trans
            try:
                old_trans.close()
            except Exception:
                pass
            self._homed = False
            return {
                "ok": True,
                "simulated": False,
                "port": port,
                "message": f"Connected to Arduino Uno on {port}",
            }
        except Exception as exc:
            return {
                "ok": False,
                "simulated": isinstance(self.transport, SimulatedTransport),
                "error": str(exc),
            }

    def home(self) -> None:
        self.command("HOME", TIMEOUT_HOME_S)
        self._homed = True
        self._moves_since_home = 0
        self._apply_speed_config()
        try:
            status = self.read_status()
            if status.homed is not None:
                self._homed = status.homed
        except Exception:
            pass

    def stop(self) -> None:
        self.command("STOP", TIMEOUT_SHORT_S)

    def magnet(self, on: bool) -> None:
        # Mark the coil as live *before* the write: if the command fails
        # half-way we must still assume it may be energised.
        if on:
            self._magnet_engaged = True
        self.command(f"MAG {'ON' if on else 'OFF'}", TIMEOUT_SHORT_S)
        if not on:
            self._magnet_engaged = False
        if MAGNET_SETTLE_S > 0:
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
            self._moves_since_home += 1
            should_home = (
                self.home_mode == "always"
                or (
                    self.home_mode == "interval"
                    and self._moves_since_home >= max(1, self.rehome_interval)
                )
            )
            if should_home:
                self.home()
                self._moves_since_home = 0
            else:
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
        """Never leave an energised coil on a halted machine.

        A failure before the magnet was ever switched on (a pre-flight check,
        say) has nothing to release, so stay off the wire entirely.
        """
        if not self._magnet_engaged:
            return
        try:
            self.transport.send("MAG OFF", TIMEOUT_SHORT_S)
        except Exception:
            pass
        finally:
            self._magnet_engaged = False

    def close(self) -> None:
        self.transport.close()
