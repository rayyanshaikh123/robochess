# RoboChess Pi Agent

This directory is the single Pi-agent implementation for the RoboChess
repository. It runs Stockfish and the Pi-authoritative game session offline,
then optionally claims, heartbeats, and synchronizes board sessions to the
backend when network access returns.

## BLE contract

One BlueZ GATT service supports both onboarding and local gameplay:

| UUID suffix | Role |
| --- | --- |
| `F00E` | Read the full board/device ID. |
| `F00F` | Authenticated control: onboarding token and game commands. |
| `F010` | Authenticated Wi-Fi provisioning request/response. |
| `F011` | Read/notify board and provisioning status. |

The short advertised name is only a discovery label (for example `RC-001`).
Flutter must scan for the service UUID and use F00E as the authoritative ID.
Use the JSON envelope and long-message chunk framing in [PROTOCOL.md](PROTOCOL.md).

The Pi agent is the controller for a RoboChess board. It runs Stockfish locally
without internet, maintains chess state, receives game commands over BLE, and
sends motion plans to an Arduino Uno gantry controller.

## What works today

- Offline terminal chess against Stockfish.
- Native Stockfish build from the included `stockfish.zip` source archive.
- Local FEN, UCI history, versioning, legal-move validation, reset, game-over,
  and recovery state.
- BLE game-command protocol and optional BlueZ GATT server.
- Acknowledged JSON-lines Uno protocol with a default simulator.
- Shared OpenCV camera capture, saved four-corner calibration, and optional
  Roboflow or local YOLO automatic move detection with stable legal-move
  filtering.

Automatic detection supports cloud-only Roboflow mode. Set
`ROBOCHESS_VISION_MODE=cloud`, `ROBOCHESS_ROBOFLOW_MODEL_URL`, and
`ROBOCHESS_ROBOFLOW_API_KEY`; no local `.pt` file is required. In `auto` mode,
Roboflow is preferred and a local model is used as fallback.

## Fast start: offline Stockfish

Run on the Pi from the repository root:

```bash
sudo apt update
sudo apt install -y build-essential unzip python3-venv python3-full

chmod +x pi_agent/install_stockfish.sh
./pi_agent/install_stockfish.sh

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r pi_agent/requirements.txt
# For automatic piece detection, also install the optional vision dependencies:
python -m pip install -r pi_agent/requirements-vision.txt

ROBOCHESS_STOCKFISH_PATH=/usr/local/bin/stockfish \
  python -m pi_agent.terminal_game
```

The installer uses `pi_agent/stockfish.zip`, clean-rebuilds it for the Pi, and
installs the verified engine at `/usr/local/bin/stockfish`. It ignores the
macOS object files stored in the archive.

You play White. Enter SAN (`e4`, `Nf3`, `O-O`) or UCI (`e2e4`) moves. Use
`reset` to restart and `quit` to exit.

## Configuration

Create a local configuration file:

```bash
cp pi_agent/.env.example pi_agent/.env
chmod 600 pi_agent/.env
```

This repository's local config enables offline BLE with
`ROBOCHESS_DEVICE_ID=robochess-pi-001`. Its short advertised name is `RC-001`;
the app should filter by the RoboChess service UUID and read the full board ID
from the Device Info characteristic. Change both IDs before adding a second
board.

| Variable | Purpose | Default |
| --- | --- | --- |
| `ROBOCHESS_STOCKFISH_PATH` | Stockfish executable | `stockfish` |
| `ROBOCHESS_ENGINE_TIME` | Think time in seconds | `0.50` |
| `ROBOCHESS_ENGINE_SKILL_LEVEL` | Engine strength, 0–20 | `10` |
| `ROBOCHESS_BLE_ENABLED` | Start BLE GATT server | `0` |
| `ROBOCHESS_BLE_ADAPTER` | Optional Bluetooth MAC address | auto-detected |
| `ROBOCHESS_BLE_NAME` | Short advertised BLE name | `RC-<last 3 ID chars>` |
| `ROBOCHESS_UNO_SIMULATOR` | Use fake Uno acknowledgements | `1` |
| `ROBOCHESS_UNO_PORT` | Arduino USB device | `/dev/ttyACM0` |
| `ROBOCHESS_UNO_BAUDRATE` | Arduino serial speed | `115200` |
| `ROBOCHESS_API_BASE` | Optional backend API | `http://localhost:8000` |
| `ROBOCHESS_DEVICE_ID` / `ROBOCHESS_DEVICE_SECRET` | Device credentials | required for full agent |
| `ROBOCHESS_MODEL_PATH` | Local YOLO `.pt` weights; empty means calibration-only | empty |
| `ROBOCHESS_AUTO_DETECT_ENABLED` | Run automatic move detection in the agent loop | `1` |

Always install Python packages inside `.venv`. Do not use `sudo pip` or
`--break-system-packages`.

## Run the board agent

The agent needs a stable board ID. A device secret is optional at first: without one it
runs locally over BLE and waits for the app to bootstrap credentials. During the
bonded onboarding flow, the app registers the stable board ID, sends the one-time
secret over BLE, and the agent stores it in `ROBOCHESS_PROVISIONING_FILE`. With a
stored secret it also performs backend pairing, heartbeats, and session sync. With
the virtual environment active:

```bash
python -m pi_agent.main
```

`pi_agent/.env` is loaded automatically for direct runs; systemd uses its
separate `/etc/robochess/pi-agent.env` file instead.

The agent starts BLE/board control even when the backend is down. It reconnects
and uploads the Pi-authoritative session snapshot when the network returns.
When `ROBOCHESS_MODEL_PATH` is empty, camera preview/calibration still work but
automatic move detection reports `model unavailable`. Set it to a local `.pt`
file after installing `requirements-vision.txt`.

The Pi also starts a local HTTP service on port `8765`. It remains available
without internet or MongoDB:

```text
GET  http://<pi-ip>:8765/local/health
GET  http://<pi-ip>:8765/local/network/status
GET  http://<pi-ip>:8765/local/camera/frame
GET  http://<pi-ip>:8765/local/camera/stream
POST http://<pi-ip>:8765/local/calibration/manual
POST http://<pi-ip>:8765/local/move/detect
POST http://<pi-ip>:8765/local/move/analyze-and-reply
```

Wi-Fi credentials are only needed when the network status is `no_wifi` or
`wifi_connected_no_internet`. Local camera calibration and game state do not
require cloud access.

## BLE setup (optional)

BLE is optional because `bluezero` requires native GTK/GLib dependencies. Only
install it when `ROBOCHESS_BLE_ENABLED=1`:

```bash
sudo apt install -y python3-gi gir1.2-glib-2.0 libcairo2-dev pkg-config cmake
source .venv/bin/activate
python -m pip install --no-deps bluezero==0.9.1
```

The current virtualenv has been enabled to see the Debian `python3-gi` package.
For a fresh install, create it with `python3 -m venv --system-site-packages .venv`.

Pair the Flutter phone using encrypted bonding before issuing game commands.
For first hardware bring-up, set `ROBOCHESS_BLE_REQUIRE_BOND=0` (the default)
so Android can write the Control characteristic without a platform-specific
bonding failure. Set it to `1` once phone pairing has been proven.
Control writes require authenticated encryption. [PROTOCOL.md](PROTOCOL.md)
defines message formats, sequencing, state responses, and backend sync.

## Arduino Uno / gantry

Begin with the simulator:

```dotenv
ROBOCHESS_UNO_SIMULATOR=1
```

For a physical Uno, find the USB serial device:

```bash
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

Then configure, for example:

```dotenv
ROBOCHESS_UNO_SIMULATOR=0
ROBOCHESS_UNO_PORT=/dev/ttyACM0
ROBOCHESS_UNO_BAUDRATE=115200
```

The Uno must acknowledge every ASCII command defined in
[PROTOCOL.md](PROTOCOL.md). The Pi handles normal moves, captures, castling,
en passant, and promotion. A missing acknowledgement stops play in recovery;
the chess state is not advanced.

Before the app begins a physical game it must call `gantry.home`, then
`gantry.status`. The Pi verifies `HOMED=1` before issuing motion. The Uno
remains responsible for limit-switch and motor safety; the Pi owns board
geometry, coordinate conversion, path planning, electromagnet sequencing, and
capture-bin coordinates.

## Camera integration

When the model is ready, send its UCI candidates to
`VisionAdapter.observe_candidates()`. It only emits a move when exactly one
legal candidate stays stable for consecutive frames. Ambiguous observations
must use the app recovery/reset flow.

## Run as a service

For an unattended board, install the project in `/opt/robochess`, create a
`robochess` service account, and keep credentials out of the repository:

```bash
sudo install -d /etc/robochess /var/lib/robochess
sudo install -m 600 pi_agent/.env.example /etc/robochess/pi-agent.env
sudo install -m 644 pi_agent/systemd/robochess-pi.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now robochess-pi
```

The service account needs `dialout` and `bluetooth` access. Confirm the
`WorkingDirectory` and virtualenv path in `systemd/robochess-pi.service` match
your `/opt/robochess` deployment.

Diagnostics:

```bash
systemctl status robochess-pi
journalctl -u robochess-pi -f
nmcli device status
/usr/local/bin/stockfish bench 16 1 1 default depth
python -m pi_agent.diagnostics
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `No module named chess` | Activate `.venv`, then run `python -m pip install -r pi_agent/requirements.txt`. |
| `externally-managed-environment` | You used system Python. Create/activate `.venv`; do not install system-wide. |
| BLE fails on Cairo/PyGObject | Install the BLE system packages, then use `requirements-ble.txt`. |
| `stockfish` not found | Run `./pi_agent/install_stockfish.sh` or set `ROBOCHESS_STOCKFISH_PATH`. |
| Uno serial port fails | Check port/cable and `dialout` membership; use the simulator first. |
