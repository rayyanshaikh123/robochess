"""
RoboChess - laptop-side serial driver for the Arduino Uno gantry firmware.

This replaces the Raspberry Pi as the host. The Uno firmware is unchanged; it
still speaks the same line protocol over USB serial:

    HOME              limit-switch homing, sets (0,0)
    MOVEXY <x> <y>    absolute move in mm
    MAG ON | MAG OFF  electromagnet (MOSFET switched)
    STATUS            report position / state
    STOP              abort
    PING              liveness check

Acks are parsed leniently (OK / DONE / ERR / ERROR / FAIL, case-insensitive)
because the exact reply strings were never written down. If the firmware turns
out to say something else, set ACK_TOKENS below or flip to timeout mode - the
raw console in the web UI shows exactly what it sends.
"""

import re
import threading
import time
import queue
import serial
import serial.tools.list_ports

import geometry as geo

BAUD_DEFAULT = 115200
UNO_RESET_SETTLE_S = 2.5      # Uno reboots when the port opens (DTR)
ACK_TOKENS_OK = ("OK", "DONE", "READY")
ACK_TOKENS_ERR = ("ERR", "ERROR", "FAIL", "ALARM")

# Generous per-command ceilings. A full-diagonal move is the slow case.
TIMEOUT_SHORT_S = 5.0         # PING / STATUS / MAG
TIMEOUT_MOVE_S = 45.0         # MOVEXY
TIMEOUT_HOME_S = 90.0         # HOME


def list_serial_ports():
    out = []
    for p in serial.tools.list_ports.comports():
        out.append({
            "device": p.device,
            "description": p.description or "",
            "hwid": p.hwid or "",
            "likely_uno": _looks_like_uno(p),
        })
    # Most-likely candidates first.
    out.sort(key=lambda d: (not d["likely_uno"], d["device"]))
    return out


def _looks_like_uno(p):
    text = ((p.description or "") + " " + (p.manufacturer or "") + " " + (p.hwid or "")).lower()
    for hint in ("arduino", "ch340", "ch341", "usb serial", "usb-serial", "wch", "ftdi", "2341:"):
        if hint in text:
            return True
    return False


# Firmware v2 answers STATUS, MOVEXY and JOG with a full state line:
#   OK X=12.50 Y=300.00 HOMED=1 MAG=OFF LIMX=0 LIMY=0
STATUS_RE = re.compile(
    r"X=(-?[\d.]+)\s+Y=(-?[\d.]+)"
    r"(?:\s+HOMED=(\d))?(?:\s+MAG=(ON|OFF))?"
    r"(?:\s+LIMX=(\d))?(?:\s+LIMY=(\d))?", re.I)


class GantryError(RuntimeError):
    pass


class GantryController:
    """
    Owns the serial port and a single worker thread. All motion is submitted
    as jobs so a 20-second move never blocks an HTTP request.
    """

    def __init__(self, log_sink=None, max_log=400):
        self._ser = None
        self._lock = threading.RLock()
        self._log = []
        self._max_log = max_log
        self._log_seq = 0
        self._log_sink = log_sink

        self._jobs = queue.Queue()
        self._worker = None
        self._stop_worker = threading.Event()
        self._abort = threading.Event()

        self.port = None
        self.baud = BAUD_DEFAULT
        self.x = 0.0
        self.y = 0.0
        self.magnet = False
        self.homed = False
        self.busy = False
        self.current_job = None
        self.last_error = None
        self.simulate = False
        self._sim_delay = 0.02
        self.lim_x = False
        self.lim_y = False
        self.firmware = None
        self.limits_mismatch = []
        self.link_down = False

    # -- logging ------------------------------------------------------------
    def log(self, text, kind="info"):
        with self._lock:
            self._log_seq += 1
            entry = {"seq": self._log_seq, "t": time.time(), "kind": kind, "text": text}
            self._log.append(entry)
            if len(self._log) > self._max_log:
                del self._log[: len(self._log) - self._max_log]
        if self._log_sink:
            try:
                self._log_sink(entry)
            except Exception:
                pass

    def absorb(self, line):
        """
        Trust the firmware over our own dead reckoning: every OK line that
        carries a position updates our idea of where the machine is.
        """
        if "READY" in line.upper() and "ROBOCHESS" in line.upper():
            self.firmware = line.strip()
            return
        m = STATUS_RE.search(line)
        if not m:
            return
        try:
            self.x = float(m.group(1))
            self.y = float(m.group(2))
        except (TypeError, ValueError):
            return
        if m.group(3) is not None:
            self.homed = (m.group(3) == "1")
        if m.group(4) is not None:
            self.magnet = (m.group(4).upper() == "ON")
        if m.group(5) is not None:
            self.lim_x = (m.group(5) == "1")
        if m.group(6) is not None:
            self.lim_y = (m.group(6) == "1")

    def log_since(self, seq):
        with self._lock:
            return [e for e in self._log if e["seq"] > seq]

    # -- connection ---------------------------------------------------------
    @property
    def connected(self):
        return self.simulate or (self._ser is not None and self._ser.is_open)

    def connect(self, port, baud=BAUD_DEFAULT, simulate=False):
        self.disconnect()
        # disconnect() sets the abort latch; clear it here so a *failed* open
        # doesn't leave a phantom "STOP latched" state behind.
        self._abort.clear()
        self.simulate = bool(simulate)
        self.link_down = False
        self.port = port
        self.baud = int(baud)
        self.last_error = None

        if self.simulate:
            self.log("SIMULATION mode - no serial port opened", "warn")
        else:
            self.log("opening %s @ %d ..." % (port, baud))
            try:
                self._ser = serial.Serial(port, int(baud), timeout=0.2, write_timeout=5)
            except Exception as exc:
                self._ser = None
                msg = str(exc)
                if "denied" in msg.lower() or "permission" in msg.lower():
                    msg += ("  --  another program is holding %s. Close the Arduino IDE's "
                            "Serial Monitor (or any other terminal / plotter using this "
                            "port) and press Connect again." % port)
                elif "could not open" in msg.lower() or "FileNotFound" in msg:
                    msg += ("  --  %s is not there any more. Unplug/replug the Uno and "
                            "press the refresh button next to the port list." % port)
                self.last_error = msg
                self.log("open failed: %s" % msg, "error")
                raise GantryError(msg)
            # The Uno resets on port open; swallow the bootloader/banner noise.
            time.sleep(UNO_RESET_SETTLE_S)
            try:
                self._ser.reset_input_buffer()
            except Exception:
                pass
            self.log("port open, Uno reset settled", "ok")

        self.homed = False
        self.magnet = False
        self.x = self.y = 0.0
        self._stop_worker.clear()
        self._abort.clear()
        self._worker = threading.Thread(target=self._run, name="gantry-worker", daemon=True)
        self._worker.start()
        self.submit("check limits", self.check_firmware_limits)
        return True

    def check_firmware_limits(self):
        """
        The firmware keeps its own soft limits in EEPROM, and reflashing does
        NOT overwrite EEPROM. So the board can happily be running last week's
        max.x/max.y while this side has new geometry - the pad then draws an
        area the firmware will refuse with ERR RANGE, which looks like a UI
        bug and isn't one. Catch that here, on connect, with the exact fix.
        """
        ok_, lines = self.send("CFG", TIMEOUT_SHORT_S)
        if not ok_ and not lines:
            return
        got = {}
        for line in lines:
            m = re.match(r"\s*(max\.[xy])\s*=\s*(-?[\d.]+)", line, re.I)
            if m:
                got[m.group(1).lower()] = float(m.group(2))
        if not got:
            return
        want = {"max.x": geo.MAX_X_MM, "max.y": geo.MAX_Y_MM}
        bad = [(k, got[k], want[k]) for k in want
               if k in got and abs(got[k] - want[k]) > 0.5]
        if bad:
            self.log("FIRMWARE SOFT LIMITS DISAGREE WITH THIS APP'S GEOMETRY", "error")
            for k, have, need in bad:
                self.log("  firmware %s = %.1f, but geometry expects %.1f"
                         % (k, have, need), "error")
            self.log("  Moves into the mismatched area will come back ERR RANGE "
                     "even though the pad draws them.", "error")
            self.log("  Fix on the Console tab: " +
                     "  ".join("SET %s %.0f" % (k, need) for k, _, need in bad),
                     "error")
            self.log("  (or send DEFAULTS to reload all factory values)", "error")
            self.limits_mismatch = ["%s=%.0f (need %.0f)" % (k, h, n) for k, h, n in bad]
        else:
            self.limits_mismatch = []
            self.log("firmware soft limits match geometry (x<=%.0f y<=%.0f)"
                     % (geo.MAX_X_MM, geo.MAX_Y_MM), "ok")

    def disconnect(self):
        self._stop_worker.set()
        self._abort.set()
        w = self._worker
        if w and w.is_alive():
            self._jobs.put(None)
            w.join(timeout=3)
        self._worker = None
        with self._lock:
            if self._ser is not None:
                try:
                    self._ser.close()
                except Exception:
                    pass
                self._ser = None
        if self.simulate:
            self.simulate = False
        self.busy = False
        self.current_job = None
        while not self._jobs.empty():
            try:
                self._jobs.get_nowait()
            except queue.Empty:
                break

    # -- raw serial ---------------------------------------------------------
    def link_lost(self, where, exc):
        """
        The port handle is dead - the device unplugged, reset, browned out or
        re-enumerated. pyserial still reports is_open == True in that state,
        so without this the app happily keeps queueing work into a handle
        that can never succeed, which is what filled the log with sixteen
        identical failed moves. Tear the link down instead so `connected`
        goes false, the UI says so, and the queue stops.
        """
        msg = ("USB serial link lost during %s: %s -- the Uno unplugged, "
               "reset or browned out. Reconnect once it is back." % (where, exc))
        self.last_error = msg
        self.link_down = True
        self.log(msg, "error")
        with self._lock:
            if self._ser is not None:
                try:
                    self._ser.close()
                except Exception:
                    pass
                self._ser = None
        self._abort.set()          # stop anything mid-sequence
        while not self._jobs.empty():
            try:
                self._jobs.get_nowait()
                self._jobs.task_done()
            except queue.Empty:
                break

    def _write_line(self, text):
        if self.simulate:
            return
        if self._ser is None or not self._ser.is_open:
            raise GantryError("not connected")
        try:
            self._ser.write((text + "\n").encode("ascii", "ignore"))
            self._ser.flush()
        except Exception as exc:
            self.link_lost("write", exc)
            raise GantryError(self.last_error)

    def send(self, command, timeout=TIMEOUT_SHORT_S):
        """
        Send one line and collect reply lines until an ack token or timeout.
        Returns (ok: bool, lines: list[str]).
        """
        with self._lock:
            self.log("> " + command, "tx")
            if self.simulate:
                time.sleep(self._sim_delay)
                self.log("< OK", "rx")
                return True, ["OK"]

            self._write_line(command)
            deadline = time.time() + timeout
            lines, ok, saw_ack = [], True, False
            buf = b""
            while time.time() < deadline:
                if self._abort.is_set():
                    break
                try:
                    chunk = self._ser.read(256)
                except Exception as exc:
                    self.link_lost("read", exc)
                    raise GantryError(self.last_error)
                if chunk:
                    buf += chunk
                    while b"\n" in buf:
                        raw, buf = buf.split(b"\n", 1)
                        line = raw.decode("utf-8", "replace").strip()
                        if not line:
                            continue
                        lines.append(line)
                        upper = line.upper()
                        if upper.startswith(ACK_TOKENS_ERR):
                            self.log("< " + line, "error")
                            return False, lines
                        self.log("< " + line, "rx")
                        self.absorb(line)
                        if upper.startswith(ACK_TOKENS_OK):
                            saw_ack = True
                    if saw_ack:
                        return True, lines
                else:
                    time.sleep(0.005)

            if not saw_ack:
                self.log("no ack for %r within %.0fs (continuing)" % (command, timeout), "warn")
                ok = False
            return ok, lines

    # -- primitives ---------------------------------------------------------
    def cmd_ping(self):
        return self.send("PING", TIMEOUT_SHORT_S)[0]

    def cmd_status(self):
        return self.send("STATUS", TIMEOUT_SHORT_S)[1]

    def cmd_stop(self):
        """Immediate - deliberately bypasses the job queue."""
        self._abort.set()
        try:
            self._write_line("STOP")
            self.log("> STOP (emergency)", "warn")
        except Exception as exc:
            self.log("STOP failed: %s" % exc, "error")
        while not self._jobs.empty():
            try:
                self._jobs.get_nowait()
                self._jobs.task_done()
            except queue.Empty:
                break

    def clear_abort(self):
        self._abort.clear()

    def cmd_home(self):
        ok, _ = self.send("HOME", TIMEOUT_HOME_S)
        if ok:
            self.x = self.y = 0.0
            self.homed = True
        return ok

    def cmd_magnet(self, on):
        ok, _ = self.send("MAG ON" if on else "MAG OFF", TIMEOUT_SHORT_S)
        if not ok and on:
            # Failing to ENGAGE must stop the sequence: dragging on to the
            # destination with no magnet just moves an empty gantry and
            # leaves the piece behind. Failing to RELEASE is logged but not
            # raised, because drag() calls it from a finally block and the
            # firmware drops the coil on STOP and at the 30 s guard anyway.
            raise GantryError("magnet did not engage")
        if ok:
            self.magnet = bool(on)
        # The firmware already dwells (mag.dwell) for the coil's field to
        # build or decay before returning, so no extra delay is needed here.
        return ok

    def cmd_movexy(self, x, y):
        if not geo.within_limits(x, y):
            msg = "refusing out-of-range move (%.1f, %.1f); limits are 0..%.0f / 0..%.0f" % (
                x, y, geo.MAX_X_MM, geo.MAX_Y_MM)
            self.log(msg, "error")
            raise GantryError(msg)
        ok, lines = self.send("MOVEXY %.2f %.2f" % (x, y), TIMEOUT_MOVE_S)
        if not ok:
            # Raise rather than return False. This is called from travel(),
            # which used to ignore the result and just carry on to the next
            # waypoint - so a refused or unacknowledged move meant the magnet
            # stayed engaged and the piece got dragged along a path the
            # gantry was never actually on, then dropped somewhere wrong.
            # Failing loudly lets game_state flag a desync instead.
            detail = lines[-1] if lines else "no acknowledgement"
            raise GantryError("MOVEXY %.2f %.2f failed: %s" % (x, y, detail))
        self.x, self.y = float(x), float(y)
        return True

    def travel(self, waypoints):
        for (x, y) in waypoints:
            if self._abort.is_set():
                raise GantryError("aborted")
            self.cmd_movexy(x, y)

    def park(self):
        return self.cmd_movexy(geo.PARK_X_MM, geo.PARK_Y_MM)

    # -- composite motions --------------------------------------------------
    def drag(self, waypoints, pickup_xy):
        """Go to pickup, magnet on, follow waypoints, magnet off."""
        self.cmd_movexy(*pickup_xy)
        self.cmd_magnet(True)
        try:
            self.travel(waypoints)
        finally:
            self.cmd_magnet(False)

    def move_square_to_square(self, from_sq, to_sq):
        self.drag(geo.plan_board_path(from_sq, to_sq), geo.square_to_mm(from_sq))

    def move_square_to_graveyard(self, from_sq, slot_index):
        slot = geo.graveyard_slot_mm(slot_index)
        self.drag(geo.plan_graveyard_path(from_sq, slot), geo.square_to_mm(from_sq))

    # -- job queue ----------------------------------------------------------
    def submit(self, name, fn):
        if not self.connected:
            raise GantryError("not connected")
        if self._abort.is_set():
            raise GantryError("aborted - press Reset/Clear before moving again")
        self._jobs.put((name, fn))
        return True

    def _run(self):
        while not self._stop_worker.is_set():
            try:
                job = self._jobs.get(timeout=0.25)
            except queue.Empty:
                continue
            if job is None:
                self._jobs.task_done()
                break
            name, fn = job
            self.busy = True
            self.current_job = name
            try:
                fn()
            except Exception as exc:
                self.last_error = str(exc)
                self.log("job %r failed: %s" % (name, exc), "error")
            finally:
                self.busy = False
                self.current_job = None
                self._jobs.task_done()

    @property
    def queued(self):
        return self._jobs.qsize()

    def state(self):
        return {
            "connected": self.connected,
            "simulate": self.simulate,
            "port": self.port,
            "baud": self.baud,
            "x": round(self.x, 2),
            "y": round(self.y, 2),
            "magnet": self.magnet,
            "homed": self.homed,
            "busy": self.busy or self.queued > 0,
            "job": self.current_job,
            "queued": self.queued,
            "aborted": self._abort.is_set(),
            "last_error": self.last_error,
            "lim_x": self.lim_x,
            "lim_y": self.lim_y,
            "firmware": self.firmware,
            "limits_mismatch": self.limits_mismatch,
            "link_down": self.link_down,
        }
