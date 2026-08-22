# RoboChess

## Physical board / Pi agent

The Raspberry Pi agent lives in [`pi_agent/`](pi_agent/README.md). It runs a
local Stockfish game and exposes the board over BLE; the Flutter application
must run on a physical Android or iPhone device near the Pi for BLE testing.
The Pi remains the authority for offline moves and synchronizes dedicated board
sessions when it reconnects to the backend.

RoboChess is a connected chess platform that combines a Flutter mobile application, a FastAPI backend, computer vision, Stockfish analysis, and an optional Raspberry Pi edge agent. Players can play games, solve puzzles, analyze positions, use voice commands, and connect the app to a physical chessboard.

## Features

- Play human-vs-human and human-vs-AI games.
- Detect board positions and infer moves from camera frames.
- Calibrate and validate a physical chessboard.
- Analyze games with Stockfish.
- Pair and monitor Raspberry Pi board devices.
- Receive game and device updates over WebSockets.
- Browse and solve chess puzzles.
- Use voice input to enter chess moves.
- Store users, devices, games, moves, puzzles, and tokens in MongoDB.

## Architecture

```text
Flutter mobile app
        | REST + WebSocket
        v
FastAPI backend  <---- optional Redis Pub/Sub for multi-instance updates
        |
        +-- MongoDB
        +-- YOLO/OpenCV board recognition
        +-- Stockfish chess engine
        +-- Raspberry Pi edge agent
```

The repository is organized into three main applications:

| Directory | Purpose |
| --- | --- |
| `frontend/` | Flutter Android application and its Clean Architecture layers |
| `backend/` | FastAPI API, authentication, game services, vision pipeline, persistence, and realtime updates |
| `pi_agent/` | Raspberry Pi client for device heartbeats, pairing, BLE advertising, and board integration |

Additional developer documentation is available in [`process.md`](process.md), [`frontend/README.md`](frontend/README.md), [`pi_agent/README.md`](pi_agent/README.md), and [`backend/engine/README.md`](backend/engine/README.md).

## Prerequisites

- Python 3.10 or newer
- Flutter 3.x with the Android toolchain configured
- MongoDB running locally or a reachable MongoDB deployment
- Stockfish installed and available on `PATH`, or supplied through `ROBOCHESS_STOCKFISH_PATH`
- A trained board-recognition model, supplied through `ROBOCHESS_MODEL_PATH`
- Optional: Redis for WebSocket fan-out across multiple backend instances
- Optional: Raspberry Pi hardware and camera for physical-board features

## Backend setup

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
cp .env.example backend/.env
```

Edit `backend/.env` before running the service. At minimum, configure a real `ROBOCHESS_JWT_SECRET`, a MongoDB URI, and paths to the board model and Stockfish binary. Never commit `.env` files or production secrets.

For a factory-provisioned board, create its backend device record once before
setup. The returned `device_id` and `device_secret` must be installed in the
Pi's protected environment file. The Flutter app uses the registered
`device_id` to request a short-lived onboarding token; it never receives the
Pi's device secret.

Start the API from the repository root:

```bash
source .venv/bin/activate
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Useful endpoints:

- Health check: <http://localhost:8000/health>
- Interactive API docs: <http://localhost:8000/docs>
- OpenAPI schema: <http://localhost:8000/openapi.json>
- WebSocket endpoint: `ws://localhost:8000/ws`

The backend initializes MongoDB during startup. Vision and engine functionality also require a usable camera, model, and Stockfish binary. The health endpoint reports whether those runtime components are ready.

## Flutter app setup

Install dependencies and run the app:

```bash
cd frontend
flutter pub get
flutter run
```

The current development default is `http://172.20.10.3:8000` for the API and
`ws://172.20.10.3:8000/ws` for WebSockets. Android emulators normally use
`10.0.2.2`; for a physical phone or a different backend host, provide the URLs
at build time:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://<backend-ip>:8000 \
  --dart-define=WS_BASE_URL=ws://<backend-ip>:8000/ws
```

The app starts at the login screen. After authentication, it exposes the home dashboard, gameplay, analysis, learning and puzzles, device connection, and profile flows.

On Android, grant Nearby devices/Bluetooth permission when prompted. The BLE
setup screen is available from Connect → Link Board → Scan and set up over
Bluetooth. Manual pairing-code entry remains available for local development.

## Raspberry Pi agent

Install the edge-agent dependencies on the Pi:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r pi_agent/requirements.txt
```

Configure the device using `pi_agent/.env.example` (or environment variables):

```dotenv
ROBOCHESS_API_BASE=http://<backend-ip>:8000
ROBOCHESS_WS_BASE=ws://<backend-ip>:8000/ws
ROBOCHESS_DEVICE_ID=<device_id>
ROBOCHESS_DEVICE_SECRET=<device_secret>
ROBOCHESS_HEARTBEAT_SECONDS=10
```

Run it from the repository root:

```bash
python3 -m pi_agent.main
```

BLE advertising can be enabled on a Raspberry Pi with the additional BLE settings documented in [`pi_agent/README.md`](pi_agent/README.md). The board-specific detection integration point is `pi_agent/vision_adapter.py`.

For unattended startup, install [`pi_agent/systemd/robochess-pi.service`](pi_agent/systemd/robochess-pi.service) on the Pi and enable it with `systemctl enable --now robochess-pi`.

## Configuration

The main configuration variables are:

| Variable | Purpose | Default |
| --- | --- | --- |
| `ROBOCHESS_MONGODB_URI` | MongoDB connection string | `mongodb://localhost:27017` |
| `ROBOCHESS_MONGODB_DB` | MongoDB database name | `robochess` |
| `ROBOCHESS_MODEL_PATH` | Board-recognition model path | `backend/models/best.pt` |
| `ROBOCHESS_STOCKFISH_PATH` | Stockfish executable path | Auto-discovered |
| `ROBOCHESS_CAMERA_INDEX` | OpenCV camera index | `0` |
| `ROBOCHESS_ENGINE_TIME` | Stockfish analysis time in seconds | `0.50` |
| `ROBOCHESS_REDIS_URL` | Optional Redis connection string | Empty |
| `ROBOCHESS_JWT_SECRET` | JWT signing secret | `change-me` |

See [`.env.example`](.env.example) for the complete list of backend, vision, authentication, rate-limit, realtime, and Pi-agent settings.

## Testing and quality checks

Run the Flutter test suite and static analysis with:

```bash
cd frontend
flutter test
flutter analyze
```

Backend load-testing utilities are provided under [`backend/load_tests/`](backend/load_tests/). Start the backend first, then run Locust according to [`backend/load_tests/README.md`](backend/load_tests/README.md).

## Security

Use strong, environment-specific secrets for JWT signing and device credentials. Keep database credentials, model files, and other local configuration out of version control. Security issues should be reported privately according to [`SECURITY.md`](SECURITY.md).

## Project status

RoboChess is under active development. The mobile, backend, vision, and Pi-agent components are present in this repository, while hardware-specific camera and board integrations may require local configuration and device testing.
