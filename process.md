# RoboChess Process Overview

This document explains how RoboChess works end-to-end from a developer perspective, including service responsibilities, board identification, and key data flows.

## User Perspective Flow

1. Install and open the mobile app.
2. Create an account or log in.
3. (Optional) Link a physical board.
4. Choose a mode:
   - Play a game (human vs AI or human vs human).
   - Solve puzzles.
   - View analysis (game insights).
5. If using a physical board:
   - Run calibration (auto or manual).
   - Validate board setup.
6. Start a game and play moves.
7. See realtime updates in the app.
8. Review results or start another session.

## System Process Flow (High Level)

- The mobile app authenticates the user and stores session tokens.
- The backend initializes services (DB, optional Redis, game manager).
- If a device is linked, the device connects and sends heartbeats.
- The user starts a game. The backend creates a game record and returns a game_id.
- The user (or the board) submits moves. The backend validates and records moves.
- Realtime updates are pushed via WebSocket to all subscribers.
- Optional: AI move or board-detected move is added, and clients receive updates.

## Developer Perspective: Components and Responsibilities

### Mobile App (Flutter)

- User authentication and token storage.
- UI for device linking, calibration, gameplay, puzzles, and analysis.
- REST calls for auth, devices, games, puzzles.
- WebSocket client for realtime game and device updates.

### Backend API (FastAPI)

- Auth service: register, login, refresh, logout.
- Device service: register/link/connect/heartbeat/status.
- Game service: create games, process moves, AI moves, and state retrieval.
- Calibration service: load model, auto/manual calibration, validate setup.
- Realtime: WebSocket endpoint for state and device updates.

### Game Manager (Backend Core)

- Singleton that holds runtime state for model, engine, and camera pipelines.
- Orchestrates board recognition and engine operations.
- Manages calibration outputs and board snapshots.

### Vision / Board Recognition

- Uses a board recognizer that loads a YOLO model.
- Captures camera frames, detects board corners, and maps to board squares.
- Converts detections into board state and move candidates.
- Validates with calibration and game rules before accepting moves.

### Realtime Layer

- WebSocket room manager to broadcast game updates to subscribed clients.
- Optional Redis pubsub for multi-instance broadcast.

### Data Stores

- MongoDB for users, devices, games, moves, puzzles, and tokens.
- Indexed collections for fast lookup and game versioning.

### Edge Device (Pi Agent)

- Connects to backend as a device.
- Sends heartbeats and (eventually) detection events.
- Runs local vision adapter for board capture (currently stubbed).

## Board Identification Pipeline (Developer View)

1. Model load: backend loads YOLO weights for board recognition.
2. Calibration: detect board corners (auto) or accept manual corners.
3. Validation: confirm board setup and orientation.
4. Capture: camera frame is captured and processed.
5. Detection: pieces/board are detected and mapped to squares.
6. Move inference: compare board states to infer move candidates.
7. Game update: validate move, persist, broadcast via WebSocket.

## Textual Diagram (Developer and System)

MOBILE APP (Flutter)
  |
  | REST: auth, devices, games, puzzles
  v
BACKEND API (FastAPI)
  |
  | calls
  v
SERVICES LAYER
  |-- Auth Service
  |-- Device Service <-------> EDGE DEVICE (Pi Agent)
  |-- Game Service
  |-- Calibration Service
  v
GAME MANAGER (Runtime)
  |-- Board Recognizer (YOLO)
  |-- Camera Capture
  |-- Stockfish Engine
  v
MONGODB (state, moves, puzzles)
  |
  | push updates
  v
REALTIME WS (+ Redis pubsub)
  |
  | updates
  v
MOBILE APP (subscribed clients)

## Mermaid Diagram

```mermaid
flowchart TD
  A[Mobile App] -->|REST| B[Backend API]
  A -->|WebSocket| G[Realtime WS]
  B --> C[Services Layer]
  C --> C1[Auth Service]
  C --> C2[Device Service]
  C --> C3[Game Service]
  C --> C4[Calibration Service]
  C2 <--> D[Edge Device (Pi Agent)]
  C3 --> E[Game Manager]
  E --> E1[Board Recognizer (YOLO)]
  E --> E2[Camera Capture]
  E --> E3[Stockfish Engine]
  C --> F[MongoDB]
  G -->|updates| A
  G <--> H[Redis PubSub (optional)]
```

## Notes

- The device agent sends heartbeat/status to the backend to indicate availability.
- Calibration is required before syncing board-detected moves.
- Realtime delivery uses WebSocket, optionally scaled by Redis pubsub.
