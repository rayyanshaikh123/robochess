# RoboChess --- Project Context

## 1. Project Overview

RoboChess is a physical robotic chess system combining:

-   A Raspberry Pi 5 edge computer
-   Camera-based ML/computer-vision board detection
-   A motorized X/Y gantry for moving chess pieces
-   Arduino/CNC motor-control hardware
-   A local chess engine (Stockfish)
-   A cloud-hosted AI model for advanced reasoning/analysis
-   A FastAPI backend
-   A Flutter mobile application
-   Bluetooth communication between the mobile app and Raspberry Pi
-   Persistent backend/database services for accounts, games, history,
    and synchronization

### Core architectural principle

**Flutter asks/displays → FastAPI coordinates/persists → Raspberry Pi
sees/executes.**

However, the physical robot must ultimately be capable of operating
independently of FastAPI and the internet.

The target architecture is therefore:

> **Raspberry Pi = autonomous edge robot**
>
> **FastAPI = cloud/application/synchronization layer**
>
> **Flutter = user interface**
>
> **Stockfish = local chess engine**
>
> **Cloud AI model = optional advanced intelligence for now; local model
> later**

------------------------------------------------------------------------

# 2. Current Progress

## Physical Hardware

### Gantry

-   Fully calibrated.
-   X/Y movement system is functional.
-   Gantry is controlled through the Arduino/CNC motor-control side.
-   Servo/electromagnet mechanism is part of the physical
    piece-manipulation system.

### Raspberry Pi

-   Raspberry Pi 5 is the edge computer.
-   Connected to the camera.
-   Connected to the hardware-control layer.
-   Intended to become the autonomous controller for the complete robot.

### Camera

-   Camera is connected to the Raspberry Pi.
-   Used for chessboard/piece observation and move detection.

### Arduino / CNC control

-   Arduino/CNC shield handles low-level motor execution.
-   Pi should issue high-level physical commands rather than exposing
    motor-step details to the app/backend.

The current circuit contains the Raspberry Pi, camera, Arduino/CNC
shield, stepper motors, servo/electromagnet hardware, power supply and
associated control electronics.

------------------------------------------------------------------------

# 3. Computer Vision / ML Progress

The ML detection pipeline is functional.

Current status:

-   Piece detection: DONE
-   Board understanding: DONE
-   Move detection: PARTIAL
-   Full reliable game-state transition from visual observations: NOT
    YET COMPLETE

Current conceptual pipeline:

Camera → frame capture → image preprocessing → ML piece detection →
board/square mapping → board state → compare previous and current state
→ candidate move → chess-rule validation → confirmed move

Example:

Before: - e2 = white pawn - e4 = empty

After: - e2 = empty - e4 = white pawn

Candidate: `e2 → e4`

The move should then be validated by the local chess rules engine before
changing authoritative game state.

------------------------------------------------------------------------

# 4. Mobile Application Progress

Flutter application is functional.

Current capabilities include:

-   Working app UI
-   Bluetooth connection to Raspberry Pi
-   Pi discovery/connection flow
-   BLE-based communication/provisioning architecture

The app should remain a UI/control layer.

It should NOT directly know: - GPIO pins - motor steps - servo angles -
CNC commands - camera internals - low-level hardware implementation

Instead, the app should send high-level commands such as:

-   START_GAME
-   PAUSE
-   RESUME
-   RESET
-   CALIBRATE
-   REQUEST_STATUS

The Pi handles the actual hardware implementation.

------------------------------------------------------------------------

# 5. FastAPI Backend

FastAPI server exists and is functional as a backend foundation.

Primary intended responsibilities:

-   Authentication
-   User management
-   Game management
-   Chess-game APIs
-   Game persistence
-   Game history
-   Statistics
-   Robot/device management
-   Pi communication/synchronization
-   WebSocket communication with the app
-   Cloud AI model integration
-   Online features

FastAPI should NOT be a hard dependency for basic physical chess
operation.

If the internet/server is unavailable, the Pi should still be capable of
playing a local chess game.

------------------------------------------------------------------------

# 6. Chess Engine Architecture

Stockfish should run locally on the Raspberry Pi.

The Pi should contain:

-   Local chess rules/state manager
-   python-chess or equivalent chess-rule implementation
-   Stockfish
-   Current FEN
-   Move history
-   Turn information
-   Castling rights
-   En-passant state
-   Game status

Core offline game loop:

Human physically moves piece → Pi detects move → Pi validates move → Pi
updates local chess state → Stockfish calculates response → Pi sends
physical movement command → Gantry moves piece → Camera verifies
resulting board → Pi updates state → repeat

This should work without FastAPI or internet.

------------------------------------------------------------------------

# 7. Cloud AI Model

The project's custom AI model currently exists in the cloud.

Local model weights have NOT yet been created/deployed.

Therefore, current AI architecture should use:

`Pi → Cloud AI API`

but should be designed so it can later become:

`Pi → Local AI model`

without rewriting the entire system.

Recommended abstraction:

``` text
AIEngine
├── CloudModel
└── LocalModel (future)
```

Current implementation:

``` text
AIEngine → CloudModel
```

Future implementation:

``` text
AIEngine → LocalModel
```

Potential final implementation:

``` text
AIEngine
├── LocalModel
└── CloudModel
```

with local inference preferred when available and cloud inference used
as an optional enhancement/fallback.

------------------------------------------------------------------------

# 8. Stockfish vs Custom AI

These are different components and should not be conflated.

## Stockfish

Purpose: - Chess move generation - Chess strength - Best-move
calculation - Offline chess operation

Stockfish is the chess engine.

## Custom AI Model

Potential purposes: - Advanced board reasoning - Vision reasoning -
Move/event analysis - Physical error detection - State-mismatch
reasoning - Natural-language explanations - Adaptive behavior - Future
research functionality

The custom AI model should not be required simply to determine a legal
chess move if Stockfish can already do that locally.

------------------------------------------------------------------------

# 9. Raspberry Pi Responsibilities

The Raspberry Pi should be treated as the autonomous edge controller.

## Pi owns

### Vision

-   Camera capture
-   Image preprocessing
-   ML inference
-   Board detection
-   Piece detection
-   Move detection
-   Physical board-state observation

### Chess

-   Local game state
-   Chess rules
-   Move validation
-   Stockfish
-   Local game execution

### Hardware

-   Arduino/CNC communication
-   X/Y gantry control
-   Servo control
-   Electromagnet/piece pickup
-   Calibration
-   Homing
-   Physical movement
-   Safety checks
-   Emergency stop
-   Hardware fault detection

### Robot state

Suggested state machine:

BOOT → INITIALIZING → READY → WAITING_FOR_MOVE → DETECTING → VALIDATING
→ THINKING → MOVING → VERIFYING → WAITING_FOR_MOVE

Possible error states:

-   ERROR
-   CALIBRATING
-   EMERGENCY_STOP
-   DISCONNECTED
-   STATE_MISMATCH
-   CAMERA_ERROR
-   MOTOR_ERROR
-   HARDWARE_ERROR

### Communication

-   Bluetooth communication with Flutter where appropriate
-   Wi-Fi/network communication with FastAPI
-   High-level robot command protocol

------------------------------------------------------------------------

# 10. FastAPI Responsibilities

FastAPI is the cloud/application layer.

## Core responsibilities

### User layer

-   Authentication
-   Registration
-   Profiles
-   Settings

### Game layer

-   Create game
-   Start game
-   End game
-   Resign
-   Game history
-   Game statistics
-   Persistent game records

### Backend chess state

The backend can maintain a synchronized copy of game state, but the Pi's
local state is required for offline operation.

Important distinction:

### Logical state

What the chess game says is on the board.

Example: - FEN - move history - turn - castling rights - en-passant

### Physical state

What the Pi's camera believes is physically on the board.

The system should compare these states.

If they differ:

`STATE_MISMATCH`

Possible causes: - Human moved a piece unexpectedly - Robot failed to
place a piece - Piece was displaced - Camera detection error -
Occlusion - Hardware movement error

### Cloud AI

-   API gateway for cloud model
-   AI inference
-   Advanced reasoning
-   Optional analysis

### Synchronization

-   Pi ↔ backend
-   App ↔ backend
-   Game-state synchronization
-   Robot status synchronization

------------------------------------------------------------------------

# 11. Flutter Responsibilities

Flutter is the user experience layer.

## Main features

-   Authentication UI
-   Home/dashboard
-   Start game
-   Game screen
-   Chessboard visualization
-   Game history
-   Statistics
-   Settings
-   Robot status
-   Connection status
-   Errors/warnings
-   Game controls

Example game UI information:

-   Current board
-   Current player/turn
-   Last move
-   Robot status
-   Thinking status
-   Movement status
-   Error state

The displayed chessboard should normally come from the authoritative
synchronized game state rather than directly rendering raw camera
detections.

------------------------------------------------------------------------

# 12. Communication Architecture

## Flutter ↔ Raspberry Pi

Bluetooth can be used for:

-   Initial pairing
-   Device discovery
-   Wi-Fi provisioning
-   Local setup
-   Basic local control
-   Status

Once the Pi has Wi-Fi, the primary Pi ↔ backend connection should
preferably use the network rather than Bluetooth.

## Raspberry Pi ↔ FastAPI

Use a persistent network connection when online.

Possible protocols: - WebSocket - MQTT - HTTP + WebSocket combination

The exact protocol can be finalized during implementation.

High-level commands from backend to Pi:

``` text
MOVE_PIECE
CALIBRATE
HOME_MOTORS
PAUSE
RESUME
STOP
RESET
REQUEST_BOARD_STATE
START_GAME
END_GAME
```

Events from Pi to backend:

``` text
PI_CONNECTED
PI_DISCONNECTED
BOARD_STATE
MOVE_DETECTED
MOVE_STARTED
MOVE_COMPLETED
MOVE_FAILED
CAMERA_ERROR
MOTOR_ERROR
HARDWARE_ERROR
EMERGENCY_STOP
STATE_MISMATCH
```

------------------------------------------------------------------------

# 13. Suggested Pi Software Structure

``` text
robochess-pi/
│
├── main.py
│
├── camera/
│   ├── camera.py
│   ├── board_detector.py
│   └── piece_detector.py
│
├── chess/
│   ├── game_state.py
│   ├── chess_rules.py
│   └── stockfish.py
│
├── robot/
│   ├── motor_controller.py
│   ├── servo_controller.py
│   ├── electromagnet.py
│   └── calibration.py
│
├── hardware/
│   ├── arduino.py
│   ├── sensors.py
│   └── safety.py
│
├── ai/
│   ├── ai_engine.py
│   ├── cloud_model.py
│   └── local_model.py
│
├── communication/
│   ├── backend_client.py
│   └── protocol.py
│
└── config/
    └── config.yaml
```

`local_model.py` can remain unused until local model weights exist.

------------------------------------------------------------------------

# 14. Critical Architecture Rule

Do NOT make the following dependency:

``` text
Flutter
→ FastAPI
→ Stockfish
→ Pi
→ Robot
```

if that means the robot stops working when the server is unavailable.

Instead:

``` text
              Raspberry Pi
        ┌─────────────────────┐
        │ Vision              │
        │ Game State          │
        │ Chess Rules         │
        │ Stockfish           │
        │ Robot Controller    │
        │ Hardware Safety     │
        └──────────┬──────────┘
                   │
             Optional online
                   │
          ┌────────┴────────┐
          ▼                 ▼
      FastAPI           Cloud AI
          │
          ▼
      Flutter
```

FastAPI and cloud AI enhance the robot rather than becoming single
points of failure.

------------------------------------------------------------------------

# 15. Offline Mode

Target behavior:

``` text
Internet OFF
     ↓
Pi boots
     ↓
Camera initialized
     ↓
Local chess state initialized
     ↓
Stockfish initialized
     ↓
Human moves piece
     ↓
Vision detects move
     ↓
Move validated locally
     ↓
Stockfish calculates response
     ↓
Gantry executes response
     ↓
Camera verifies movement
     ↓
Game continues
```

No FastAPI dependency.

No cloud AI dependency.

------------------------------------------------------------------------

# 16. Online Mode

When internet is available:

``` text
Flutter
   ↕
FastAPI
   ↕
Raspberry Pi
   ↕
Cloud AI
```

The Pi continues to own physical execution and local chess capability.

Cloud services provide: - synchronization - persistence - remote UI - AI
model inference - online features - analytics

------------------------------------------------------------------------

# 17. Current Priority Roadmap

## Completed

1.  Gantry calibration
2.  ML piece-detection pipeline
3.  Camera integration
4.  Flutter application
5.  Bluetooth app ↔ Pi connection
6.  FastAPI foundation
7.  Cloud AI model

## Immediate next priorities

8.  Finish reliable move detection
9.  Build local chess-state manager
10. Integrate Stockfish on Pi
11. Implement Pi state machine
12. Connect move detection to chess-rule validation
13. Connect Stockfish response to gantry
14. Add physical move verification
15. Make a complete offline game work

## After offline core works

16. Define Pi ↔ FastAPI protocol
17. Connect Pi to FastAPI over Wi-Fi
18. Integrate cloud AI
19. Synchronize Pi ↔ backend ↔ Flutter
20. Persist games
21. Add online/offline modes

## Final robustness work

22. State mismatch detection
23. Hardware fault recovery
24. Emergency-stop handling
25. Camera failure handling
26. Motor failure handling
27. Game recovery after Pi reboot
28. Offline → online synchronization
29. Telemetry/logging
30. Performance optimization
31. Local AI model deployment when weights are available

------------------------------------------------------------------------

# 18. Key Milestone

The next major milestone is NOT another UI feature.

The target is:

> **Unplug the internet, place a valid chess position on the board, make
> a legal physical move, have the Pi detect it, validate it, let
> Stockfish calculate a response, physically move the responding piece
> with the gantry, and use the camera to verify the resulting board
> state.**

Once this works reliably, the core RoboChess system exists.

Everything afterward is primarily cloud integration, application
functionality, robustness, and advanced AI.

------------------------------------------------------------------------

# 19. One-Line Responsibility Summary

  Component      Responsibility
  -------------- ---------------------------------------------------------
  Raspberry Pi   Autonomous physical robot + vision + local chess
  Camera         Observe physical board
  ML pipeline    Detect pieces/board/moves
  Arduino/CNC    Low-level motor execution
  Gantry         Physically move pieces
  Stockfish      Local chess decision engine
  Custom AI      Advanced reasoning/analysis; cloud for now
  FastAPI        Cloud backend, synchronization, persistence, AI gateway
  Flutter        UI, user interaction, status and game visualization
  Database       Users, games, history, statistics, robot metadata

------------------------------------------------------------------------

# 20. Core Mental Model

``` text
FLUTTER
"What does the user want to do?"
        ↓
FASTAPI
"What game/application state should exist?"
        ↓
RASPBERRY PI
"What is physically happening and how do I execute it?"
        ↓
HARDWARE
"Move the piece."
```

And locally on the Pi:

``` text
CAMERA
"What is physically on the board?"
        ↓
VISION
"What changed?"
        ↓
CHESS RULES
"Is that move legal?"
        ↓
STOCKFISH
"What should the robot play?"
        ↓
ROBOT CONTROLLER
"How do I physically execute it?"
        ↓
CAMERA
"Did the physical result match the expected state?"
```

This document is the current working system-design context for RoboChess
and should be updated whenever a major architectural decision changes.
