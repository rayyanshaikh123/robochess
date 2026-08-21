# RoboChess — laptop control (no Raspberry Pi)

The Arduino Uno was always doing the real work: step generation, limit-switch
homing, soft limits, the electromagnet. The Raspberry Pi was only a *host* —
something to type serial commands at the Uno and hold the chess rules.

**Your laptop can be that host.** Same USB cable, same serial protocol, same
firmware. Nothing on the Uno changes.

```
  laptop (this code)                    Arduino Uno (unchanged firmware)
  ┌────────────────────┐   USB serial   ┌──────────────────────────────┐
  │ browser UI         │  115200 baud   │ robochess_gantry.ino         │
  │  ├ XY pad          │ ─────────────► │  HOME / MOVEXY / MAG / STOP  │
  │  └ chess board     │                │  AccelStepper + A4988 x2     │
  │ Flask + pyserial   │ ◄───────────── │  limit switches, magnet FET  │
  │ python-chess rules │   OK / ERR     └──────────────────────────────┘
  └────────────────────┘
```

## Why the Uno is enough

| | needed | Uno has |
|---|---|---|
| Step/dir for 2× A4988 | 4 pins (+1 shared EN) | 20 I/O |
| Limit switches | 2 pins | ✔ |
| Electromagnet MOSFET | 1 digital pin | ✔ |
| Firmware size | 10,044 bytes | 32,256 bytes flash |
| Real-time step timing | hard requirement | ✔ (this is exactly what an MCU is for) |
| Chess rules, UI, graphics | — | done on the laptop |

The Pi would only have added a screen and a place to run Python. You already
have both, in the laptop.

**The one trade-off:** the laptop must stay plugged in over USB while playing.
If you later want the board to run standalone, that's when a Pi (or an ESP32
with WiFi) earns its place — the whole `MOVEXY`-based interface here ports over
unchanged.

---

## Setup (Windows)

1. Install Python 3 from python.org — **tick "Add python.exe to PATH"**.
2. Plug in the Uno. If Device Manager shows an unknown device, install the
   CH340 driver (clone boards) or the official Arduino driver (genuine boards).
3. Double-click **`run.bat`**. First run builds a virtual environment and
   installs Flask, pyserial and python-chess; later runs start straight away.
4. The browser opens at <http://127.0.0.1:8000>.

Manual equivalent:

```bat
py -3 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python server.py
```

Extra flags: `--port 9000`, `--no-browser`, and `--lan` (listen on all
interfaces so you can also open the UI from your phone on the same WiFi).

### Connecting

Pick the COM port from the dropdown (likely candidates are marked ★), check the
baud matches `Serial.begin()` in the firmware — default here is **115200** —
and press **Connect**.

Opening the port resets the Uno; the driver waits 2.5 s for it to reboot before
sending anything.

### Troubleshooting connection

| symptom | cause | fix |
|---|---|---|
| `PermissionError(13, 'Access is denied.')` | Windows gives one process exclusive access to a COM port, and something else already has it | **Close the Arduino IDE's Serial Monitor / Serial Plotter** — this is the cause ~90% of the time. Also check for another copy of this server still running, PuTTY, or any slicer/CNC sender. Then press Connect again. |
| `could not open port` / `FileNotFoundError` | the Uno enumerated on a different COM number, or the cable is data-less | Unplug/replug, press the ↻ refresh button, re-pick the port. Confirm the number in Device Manager → Ports (COM & LPT). |
| Connects, but every command logs `no ack` | baud mismatch | Match the baud dropdown to `Serial.begin()` in `robochess_gantry.ino`. |
| Connects, log stays silent | wrong device (Bluetooth/virtual COM port), or the firmware isn't flashed | Look for the ★ marker in the port list; re-upload the sketch from the Arduino IDE (then close the IDE's monitor again). |

You cannot have the Arduino IDE's Serial Monitor and this server open at the
same time. Upload the sketch, close the monitor, then connect here.

> **Tick "Simulate" to drive the whole UI with no hardware attached.** Every
> command is logged but nothing is sent. Good for checking coordinates before
> the frame exists.

---

## Tab 1 — XY Pad

A scale drawing of the real travel envelope (560 × 450 mm). Click anywhere and
the gantry goes there.

- Grey field = full travel. Blue grid = the 8×8 board. Purple strip = the
  captured-piece parking area, on the right (far +X end). Green circle
  bottom-left = home (0,0).
- The orange crosshair tracks the gantry's actual reported position.
- **magnet engaged while moving** — energises the coil before the move, so you
  can drag a piece around freely by clicking.
- **snap to square centres** — clicks land on the exact square centre instead of
  wherever the pixel was. Useful for calibration.
- Right-hand panel: numeric goto, jog buttons, `HOME` (real limit-switch
  homing), `Return to 0,0` (a plain rapid — no switch wear), magnet on/off.

Out-of-range clicks are rejected by the server before anything is sent to the
firmware.

## Tab 2 — Chess

Click a piece → legal destinations light up (dots for quiet moves, red rings for
captures) → click one. The gantry executes it, then **re-homes against the
limit switches** so the next move starts from a known-true zero.

**After each move** you can choose (dropdown on the Chess tab):

| mode | what it does | when |
|---|---|---|
| `re-home on limit switches` | drives into the switches and re-zeros | **default** — immune to belt slip, costs a couple of seconds |
| `rapid to 0,0` | dead-reckoned return | faster, but slip accumulates silently |
| `stay put` | ends where the move ended | bench testing |

Belt slip is why re-homing is the default: a rapid to 0,0 lands slightly off
each time and the error compounds until pieces start missing their squares.
Touching the switches every move throws that error away instead of banking it.

Rules come from python-chess, so:

- **Illegal moves never reach the gantry** — they're refused in software.
- **Captures** park the victim in the strip *first*, then drag the capturing
  piece in.
- **En passant** parks the pawn on its actual square (e.g. f5 on `exf6`), not
  the destination square.
- **Castling** is two drags: king first, then rook.
- **Promotion** drags the pawn and prints a note — there is still no mechanism
  to swap in a queen, so do that by hand.
- You can also type moves: `Nf3`, `exd5`, `O-O`, or UCI like `g1f3`.

**Piece routing avoids collisions.** Sliding pieces go centre-to-centre (the
squares between are empty by definition of a legal move). Knights and trips to
the parking strip are routed along the gaps *between* squares — half a square
sideways, run the long leg on the gridline, then step into the destination.

**Desync handling.** Tracked state only advances after every physical action
succeeds. If a move dies half-way, a red banner tells you exactly how far it
got, further moves are blocked, and you fix the pieces by hand and press
**Resync**. "Take back" is software-only — it does not move pieces back.

## Tab 3 — Console

Type raw firmware commands (`HOME`, `MOVEXY x y`, `MAG ON`, `STATUS`, `STOP`,
`PING`, `CFG`, `SET <key> <value>`) and see the exact reply.

**If the magnet is on when it should be off**, your MOSFET stage inverts the
gate signal — send `SET mag.high 0`. The default (`1`) suits the usual
N-channel low-side MOSFET, where driving the gate HIGH energises the coil.

The log strip at the bottom of every tab shows all traffic: blue `>` sent,
green `<` received.

---

## Calibration — do this before running with pieces on the board

Every number below is **calculated from your stated dimensions, not measured**.

| constant | value | where |
|---|---|---|
| `MAX_X_MM` / `MAX_Y_MM` | 560 / 450 | `geometry.py` **and** the firmware (`max.x`/`max.y`) |
| `ORIGIN_OFFSET_X/Y_MM` | 50 / 50 | `geometry.py` |
| `SQUARE_SIZE_MM` | 50 | `geometry.py` |
| parking strip | x 450–560 (+X end), 3 deep × 8 ranks | `geometry.py` |
| `A1_AT_HOME_CORNER` | `True` | `geometry.py` |

Suggested bring-up order:

1. Connect with the motors powered but **no pieces on the board**.
2. `HOME`. Confirm it stops on both switches and calls that corner (0,0).
3. On the XY pad, tick *snap to square centres* and click **a1**. Measure where
   the magnet actually sits. Adjust `ORIGIN_OFFSET_*` by the error.
4. Click **h8**. If a1 is right but h8 drifts, your `SQUARE_SIZE_MM` (or the
   firmware's steps-per-mm) is off — the drift is 7 squares' worth of error.
5. Click a few parking slots. Confirm nothing crashes into the far frame rail.
6. Put one piece on e2 and play `e4`. Watch the magnet engage/disengage timing.
7. Only then set up a full board.

### Still open from the previous pass

- The 15 cm structural frame offset vs the 11 cm usable parking depth are
  different numbers — confirm which is real once the frame exists.
- The parking strip is on the +X side (confirmed 2026-08-20). The 15 cm gap
  on the +Y side is unused frame.
- If the board ends up mounted with h8 at the home corner instead of a1, flip
  `A1_AT_HOME_CORNER` in `geometry.py`.
- A4988 current-limit tuning per motor; magnet-arm engage angle and dwell.

### If the firmware doesn't reply the way this driver expects

Acks are parsed leniently: any line starting with `OK`, `DONE` or `READY`
counts as success, `ERR`/`ERROR`/`FAIL`/`ALARM` as failure. If the log shows
`no ack for ... within Ns`, look at what the Uno actually printed in the
console and adjust `ACK_TOKENS_OK` / `ACK_TOKENS_ERR` at the top of
`gantry.py`.

---

## Files

```
robochess_laptop/
├── run.bat            one-click Windows launcher
├── requirements.txt
├── server.py          Flask app + JSON API
├── gantry.py          serial driver, job queue, soft limits
├── geometry.py        square↔mm, parking slots, collision-free path planning
├── game_state.py      python-chess rules → physical action sequences
└── static/index.html  the whole UI, single self-contained file
```

## Verified

Dry-run suite (no hardware) covering geometry round-trips, all 24 parking slots
inside soft limits, knight/graveyard gridline routing, pad clicks including
out-of-range rejection, capture ordering, en passant square selection, both
castling sides, promotion notes, illegal moves producing zero motion, a 28-ply
Najdorf emitting 112 `MOVEXY` commands all inside the envelope, and mid-move
failure correctly flagging desync without advancing tracked state.
**60 / 60 checks passed.** UI additionally rendered and clicked through in a
real browser.
