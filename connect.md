# RoboChess — BLE Pairing & Wi-Fi Provisioning

## 1. Purpose

This module is responsible for making a Raspberry Pi-based RoboChess physical board easy to set up without SSH, manually editing configuration files, or requiring a fixed Wi-Fi network.

The system must allow a user to:

1. Discover nearby RoboChess boards from the Flutter app.
2. Select a specific physical board.
3. Establish a secure BLE connection with that board.
4. Pair the board with the user's RoboChess account/device session.
5. Provide Wi-Fi SSID and password through the Flutter app.
6. Send the Wi-Fi credentials securely to the Raspberry Pi over BLE.
7. Have the Raspberry Pi connect to the configured Wi-Fi automatically.
8. Have the Pi connect outbound to the hosted RoboChess FastAPI backend.
9. Authenticate itself using its device identity/secret.
10. Report its online status through the existing heartbeat mechanism.
11. Allow the Flutter app to display the board as online and ready.

The Raspberry Pi must operate autonomously after setup.

---

# 2. Core Architecture

The system uses three different communication mechanisms for different purposes.

```text
                    ┌─────────────────────┐
                    │    Flutter App      │
                    │       Phone         │
                    └─────────┬───────────┘
                              │
                         BLE │
                              │
                    Discovery + Pairing
                    Wi-Fi Provisioning
                              │
                              ▼
                    ┌─────────────────────┐
                    │   Raspberry Pi 5    │
                    │    RoboChess Agent  │
                    └─────────┬───────────┘
                              │
                           Wi-Fi
                              │
                              ▼
                         Internet
                              │
                       HTTPS / WSS
                              │
                              ▼
                    ┌─────────────────────┐
                    │   FastAPI Backend   │
                    │   RoboChess Server  │
                    └─────────┬───────────┘
                              │
                              ▼
                           MongoDB
```

## Communication responsibilities

### BLE

BLE is used for:

* Nearby board discovery
* Selecting a physical board
* Initial board pairing
* Wi-Fi credential provisioning
* Local setup/status communication

BLE is NOT intended to carry normal game traffic or continuous camera data.

### Wi-Fi / Internet

Wi-Fi is used for:

* Pi → FastAPI communication
* Device heartbeat
* Game events
* Board detection events
* Commands
* API requests
* WebSocket communication

### FastAPI

The backend remains the central authority for:

* User authentication
* Device registration
* Device ownership/pairing
* Device status
* Game state
* Realtime updates
* Persistence

---

# 3. First-Time Setup Flow

The complete first-time setup should work as follows:

```text
User powers ON RoboChess Pi
            │
            ▼
       Pi boots Linux
            │
            ▼
      Pi Agent starts
            │
            ▼
    Check saved Wi-Fi
            │
       ┌────┴────┐
       │         │
     FOUND     NOT FOUND
       │         │
       │         ▼
       │     Start BLE
       │     advertising
       │         │
       │         ▼
       │    Flutter scans
       │         │
       │         ▼
       │    User selects
       │       board
       │         │
       │         ▼
       │      BLE Pair
       │         │
       │         ▼
       │   Send Wi-Fi
       │    credentials
       │         │
       │         ▼
       │    Save credentials
       │         │
       └────┬────┘
            ▼
       Connect to Wi-Fi
            │
            ▼
        Internet
            │
            ▼
      FastAPI Server
            │
            ▼
     Device Authentication
            │
            ▼
       Send Heartbeat
            │
            ▼
       Board ONLINE
```

---

# 4. Important Terminology

Do not confuse these concepts:

### BLE pairing

Means:

> The Flutter application has established a local connection with a specific physical RoboChess Pi.

### Wi-Fi provisioning

Means:

> The Flutter application has supplied the Pi with credentials that allow it to join a Wi-Fi network.

### Server registration

Means:

> The Pi has authenticated itself with the RoboChess backend using its device identity.

These are three separate stages.

```text
BLE Pairing
     ↓
Wi-Fi Provisioning
     ↓
Server Connection
```

---

# 5. Multiple Boards in the Same Location

The system must support multiple RoboChess boards operating nearby.

Example:

```text
RoboChess-001
RoboChess-002
RoboChess-003
RoboChess-004
RoboChess-005
```

Each Pi must have a unique permanent device ID.

Example:

```text
rc_8f72a91c
rc_92ab812e
rc_31de772a
```

The BLE advertised name may be human-readable:

```text
RoboChess-001
```

but the BLE name must NOT be treated as the security identity.

The backend/device ID is the authoritative identity.

---

# 6. Device Identity

Each Raspberry Pi has:

```text
device_id
device_secret
```

These correspond to the existing RoboChess Pi configuration:

```env
ROBOCHESS_DEVICE_ID=<device_id>
ROBOCHESS_DEVICE_SECRET=<device_secret>
```

The device secret proves to the backend:

> This connection is coming from the registered RoboChess device.

The Flutter user's JWT proves:

> This request is coming from an authenticated RoboChess user.

The pairing process associates the two.

Conceptually:

```text
User
 │
 │ authenticated with JWT
 ▼
RoboChess Account
 │
 │ owns / controls
 ▼
Device ID
 │
 ▼
Raspberry Pi
```

---

# 7. BLE Discovery

The Raspberry Pi should advertise a RoboChess-specific BLE service.

Conceptually:

```text
BLE Advertisement

Device Name:
RoboChess-001

Service:
RoboChess Provisioning Service

Device ID:
rc_8f72a91c
```

The Flutter application scans for the RoboChess BLE service.

It should display only relevant RoboChess boards.

Example:

```text
Nearby RoboChess Boards

┌──────────────────────────────┐
│ 🤖 RoboChess-001             │
│    Signal: Strong            │
├──────────────────────────────┤
│ 🤖 RoboChess-002             │
│    Signal: Medium            │
├──────────────────────────────┤
│ 🤖 RoboChess-003             │
│    Signal: Strong            │
└──────────────────────────────┘
```

The user selects one board.

---

# 8. BLE Pairing

After the user selects a board:

```text
Flutter
   │
   │ BLE connect
   ▼
Raspberry Pi
```

The app should verify the board identity.

The Pi should expose the necessary GATT characteristics for:

* Device identification
* Pairing/authentication
* Provisioning status
* Wi-Fi provisioning
* Connection status

The exact UUIDs should be defined as constants and shared between the Flutter and Pi implementations.

Do not scatter UUID strings throughout the codebase.

---

# 9. Wi-Fi Provisioning

After BLE pairing, the Flutter app presents:

```text
Connect RoboChess Board

Wi-Fi Network
[ MyPhoneHotspot ]

Password
[ *************** ]

          [ Connect ]
```

The user provides the SSID and password.

The Flutter application sends the credentials over the established BLE connection.

Conceptually:

```text
Flutter
   │
   │ BLE
   │
   │ SSID
   │ Password
   ▼
Raspberry Pi
```

The Pi then:

1. Validates the received provisioning payload.
2. Saves the Wi-Fi credentials securely.
3. Attempts to connect to the network.
4. Checks whether it has network connectivity.
5. Attempts to reach the RoboChess backend.
6. Reports the result back to the Flutter app.

---

# 10. Phone Hotspot Scenario

The primary competition/demo scenario is a phone hotspot.

Example:

```text
Phone hotspot

SSID:
Rayyan-Hotspot

Password:
********
```

The flow is:

```text
Phone
 │
 │ Hotspot
 ▼
Wi-Fi Network
 │
 ▼
Raspberry Pi
 │
 │ Internet
 ▼
RoboChess FastAPI Server
```

The phone's hotspot is simply the Pi's Internet gateway.

The Internet connection is NOT transported through BLE.

BLE only transfers the Wi-Fi credentials during provisioning.

---

# 11. After Successful Wi-Fi Provisioning

Once the Pi has valid Wi-Fi credentials:

```text
Pi
 │
 ▼
Wi-Fi
 │
 ▼
Internet
 │
 ▼
ROBOCHESS_API_BASE
 │
 ▼
FastAPI
```

The Pi should then connect to:

```env
ROBOCHESS_API_BASE=https://api.robochess.com
ROBOCHESS_WS_BASE=wss://api.robochess.com/ws
```

The actual production URLs should come from environment/configuration and must not be hardcoded.

---

# 12. Device Authentication

After obtaining Internet access:

```text
Pi
 │
 │ device_id + device_secret
 ▼
FastAPI
```

The backend validates the device.

If valid:

```text
Device authenticated
        ↓
Heartbeat started
        ↓
Device ONLINE
```

The existing Pi configuration already specifies:

```env
ROBOCHESS_DEVICE_ID=<device_id>
ROBOCHESS_DEVICE_SECRET=<device_secret>
ROBOCHESS_HEARTBEAT_SECONDS=10
```

The heartbeat interval should remain configurable.

---

# 13. Backend Device State

The backend should maintain device status conceptually like:

```json
{
  "device_id": "rc_8f72a91c",
  "status": "online",
  "last_heartbeat": "...",
  "wifi_connected": true,
  "backend_connected": true
}
```

Possible states:

```text
UNPAIRED
BLE_CONNECTED
PROVISIONING_WIFI
WIFI_CONNECTING
WIFI_CONNECTED
SERVER_CONNECTING
ONLINE
OFFLINE
ERROR
```

The exact state model can be simplified during the first implementation.

---

# 14. Automatic Boot Behavior

After initial provisioning, the Pi must NOT require SSH or manual commands.

The intended boot sequence is:

```text
Power ON
   ↓
Linux Boot
   ↓
Network Manager starts
   ↓
Saved Wi-Fi connection attempted
   ↓
Wi-Fi connected
   ↓
Internet available
   ↓
systemd starts pi_agent
   ↓
Pi authenticates with FastAPI
   ↓
Heartbeat begins
   ↓
BLE advertising begins
   ↓
Board becomes ONLINE
```

The Pi agent should be configured as a `systemd` service.

Conceptually:

```text
robochess-pi.service
        │
        ▼
python3 -m pi_agent.main
```

---

# 15. No Fixed IP Requirement

The Pi does NOT need a fixed local IP address for the production architecture.

For example, the Pi might receive:

```text
192.168.43.20
```

from one hotspot and:

```text
192.168.43.25
```

from another.

This does not matter because the Pi initiates the connection outbound:

```text
Pi ───────────────► FastAPI
```

The Pi connects using the configured server domain rather than relying on its own local IP.

---

# 16. Reboot Behavior

Once Wi-Fi credentials are saved:

```text
Pi powers OFF
      ↓
Pi powers ON
      ↓
Linux boots
      ↓
Wi-Fi automatically reconnects
      ↓
Pi Agent starts
      ↓
FastAPI connection
      ↓
Heartbeat
      ↓
ONLINE
```

The user should not have to repeat Wi-Fi provisioning unless:

* The Wi-Fi password changed.
* The network is unavailable.
* The user explicitly requests network reconfiguration.

---

# 17. Reconfiguration

The Flutter app should eventually provide:

```text
Board Settings

RoboChess-001

Status: 🟢 Online

Network
Connected to: Rayyan-Hotspot

[ Change Wi-Fi ]

[ Disconnect Board ]

[ Unpair Board ]
```

Selecting `Change Wi-Fi` initiates BLE provisioning again.

---

# 18. Game Communication After Setup

Once the board is online, normal communication does NOT use BLE.

The architecture becomes:

```text
             Flutter
                │
          REST / WebSocket
                │
                ▼
             FastAPI
                │
        ┌───────┴────────┐
        │                │
       Game           Device
      Manager         Manager
        │                │
        └───────┬────────┘
                │
              Pi
                │
              Wi-Fi
```

BLE is therefore a setup/control channel, not the main gameplay transport.

---

# 19. Example Complete Scenario

### Step 1

User powers on the board.

```text
Pi → Boot
```

### Step 2

Pi starts BLE advertising.

```text
RoboChess-001
```

### Step 3

User opens Flutter.

```text
Scan Nearby Boards
```

### Step 4

User selects:

```text
RoboChess-001
```

### Step 5

BLE connection established.

```text
Phone ←──── BLE ────→ Pi
```

### Step 6

Flutter requests Wi-Fi configuration.

```text
SSID:
Rayyan-Hotspot

Password:
********
```

### Step 7

Flutter sends credentials over BLE.

```text
Phone ───── BLE ─────► Pi
```

### Step 8

Pi connects to hotspot.

```text
Pi ───── Wi-Fi ─────► Phone Hotspot
```

### Step 9

Pi reaches the Internet.

```text
Pi ───── Internet ─────► FastAPI
```

### Step 10

Pi authenticates.

```text
device_id
device_secret
```

### Step 11

Backend marks the device online.

```text
RoboChess-001
🟢 ONLINE
```

### Step 12

User can start a game.

```text
Flutter
   │
   ▼
FastAPI
   │
   ▼
RoboChess Pi
```

---

# 20. Implementation Boundaries

## Flutter

Responsible for:

* BLE scanning
* Displaying nearby RoboChess boards
* BLE connection
* Pairing flow
* Wi-Fi credential input
* Sending Wi-Fi credentials
* Showing provisioning progress
* Showing board/network status
* Managing the user's authentication/session

## Raspberry Pi Agent

Responsible for:

* BLE advertising
* BLE GATT server
* Pairing handshake
* Receiving Wi-Fi credentials
* Saving Wi-Fi configuration
* Connecting to Wi-Fi
* Detecting Internet availability
* Connecting to FastAPI
* Device authentication
* Heartbeat
* Device status
* Camera/hardware integration

## FastAPI Backend

Responsible for:

* User authentication
* Device registration
* Device identity validation
* Pairing authorization
* Device status
* Heartbeat tracking
* Game management
* Realtime communication

## MongoDB

Responsible for persistent storage of:

* Users
* Devices
* Pairing relationships
* Games
* Moves
* Tokens
* Device metadata

---

# 21. Important Design Rule

Do NOT make the Flutter application directly responsible for maintaining the Pi's Internet connection.

Flutter only provides the credentials:

```text
Flutter
    │
    │ BLE
    ▼
Pi
    │
    │ Wi-Fi
    ▼
Internet
```

The Pi must independently manage its network connection.

This allows the board to continue operating even if the Flutter application is closed after setup.

---

# 22. Target Architecture

The final architecture should conceptually be:

```text
                         ROBOCHESS CLOUD
                              │
                         HTTPS / WSS
                              │
                     ┌────────▼────────┐
                     │ FastAPI Backend │
                     └────────┬────────┘
                              │
                         Internet
                              │
                       Wi-Fi / Hotspot
                              │
                     ┌────────▼────────┐
                     │ Raspberry Pi 5 │
                     │                 │
                     │ Pi Agent        │
                     │ BLE             │
                     │ Camera          │
                     └────────┬────────┘
                              ▲
                              │ BLE
                              │
                     ┌────────┴────────┐
                     │ Flutter Mobile  │
                     │      App        │
                     └─────────────────┘

BLE:
Discovery → Pairing → Wi-Fi Provisioning

Wi-Fi:
Pi → Internet → FastAPI

REST/WebSocket:
Flutter ↔ FastAPI

Hardware:
Pi → Camera/Board
```

## 23. Development Order

Implement this feature in the following order:

### Phase 1 — Pi BLE advertising

Make the Pi advertise:

```text
RoboChess-<device>
```

and expose a RoboChess BLE service.

### Phase 2 — Flutter BLE discovery

Flutter scans and displays nearby RoboChess boards.

### Phase 3 — BLE connection

Flutter can connect to a selected Pi and retrieve its device ID.

### Phase 4 — Pairing

Implement the pairing/authentication handshake between Flutter, Pi, and FastAPI.

### Phase 5 — Wi-Fi provisioning

Flutter sends SSID/password over the established BLE connection.

### Phase 6 — Pi Wi-Fi manager

Pi saves credentials and automatically connects to the configured network.

### Phase 7 — Backend connection

Pi connects to the configured FastAPI URL.

### Phase 8 — Device authentication

Pi authenticates using its device credentials.

### Phase 9 — Heartbeat

Pi sends periodic heartbeat/status updates.

### Phase 10 — Automatic startup

Configure the Pi agent as a systemd service.

### Phase 11 — Flutter status

Display:

```text
BLE: Connected
Wi-Fi: Connected
Internet: Connected
Server: Connected
Board: Online
```

### Phase 12 — Integrate with game/vision pipeline

Only after the networking/provisioning system is stable should the camera, board recognition, move inference, and gameplay communication be integrated.

---

## Final Principle

The RoboChess networking model is:

```text
BLE = "Which board am I connecting to?"
        +
BLE = "How do I configure this board?"

Wi-Fi = "How does the Pi reach the Internet?"

FastAPI = "How does the RoboChess system communicate?"

WebSocket = "How do realtime game/device updates flow?"
```

The Pi should be completely autonomous after setup:

```text
POWER ON
   ↓
AUTO Wi-Fi
   ↓
AUTO INTERNET
   ↓
AUTO FASTAPI CONNECTION
   ↓
AUTO HEARTBEAT
   ↓
BOARD ONLINE
```
