# Pi gameplay protocols

## BLE GATT control protocol

Use the existing Control characteristic. Every JSON envelope uses protocol version `1`, a `request_id`, and `data.client_seq`. The paired/bonded client sends strictly increasing sequence numbers. Repeating a completed sequence returns its cached response; lower unseen sequences are rejected.

Messages are `session.start` (`initial_fen` optional, `human_color`), `move.propose` (`uci`, `expected_version`), `session.reset` (`initial_fen` optional), `session.resume`, `state.request`, `gantry.home`, and `gantry.status`. Responses are `control.result`; the Status characteristic exposes the newest `game.state` envelope. The state contains FEN, UCI history, version, phase, state hash and recovery error.

During hardware bring-up the app can also send `camera.calibrate` with
`camera_index`, `rotation` (0, 90, 180, or 270), and `board_orientation`
(`white_bottom` or `black_bottom`). The Pi persists these settings for the
future OpenCV detector; it does not claim that a camera/model is calibrated
until the detector integration exists.

The BlueZ deployment must require encrypted, bonded pairing before exposing gameplay control. The Flutter app performs bonding, stores the board identity, subscribes to status notifications, and presents manual setup/recovery actions.

### Transport framing for Android and iPhone

Small messages are one UTF-8 JSON BLE write/notification. Long Pi responses
are sent as compact chunk frames: `{"v":"1","t":"chunk","id":"request-id","d":"device-id","i":0,"n":3,"p":"base64"}`. Reassemble frames by `id`, sort by `i`, concatenate base64-decoded `p` values after all `n` chunks arrive, then decode the resulting UTF-8 JSON envelope. Discard incomplete sequences after 10 seconds and request state again. App-to-Pi JSON may be fragmented across multiple writes; the Pi reassembles it before parsing.

## Uno ASCII serial protocol

The Pi owns chess-to-coordinate conversion and sends one uppercase command per
line at 115200 baud. The Uno returns one or more lines, terminating success
with `OK`, `DONE`, or `READY`, and failure with `ERR`, `ERROR`, `FAIL`, or
`ALARM`.

Supported commands are `PING`, `STATUS`, `HOME`, `MOVEXY <x_mm> <y_mm>`,
`JOG <axis> <mm>`, `MAG ON|OFF`, and `STOP`. The Pi retries failed commands
according to its timeout policy, releases the magnet on motion failure, and
enters game recovery when execution cannot be verified.

Before physical move execution, the Flutter/iPhone app should send
`gantry.home`; the Pi verifies `HOMED=1` through `STATUS` and refuses to issue
`MOVEXY` otherwise. Limit-switch supervision and low-level motor safety remain
inside the Uno. Coordinate conversion, path planning, electromagnet timing,
and capture-bin handling remain in the Pi.

## Backend reconciliation endpoint

Implement `POST /device/session/sync` authenticated as the Pi device. Request is the local snapshot: `session_id`, `initial_fen`, `moves`, `version`, and `state_hash`. The backend deduplicates identical session/hash uploads. On a mismatch it persists a conflict record and returns it; it must never replace Pi history or silently merge moves.

The integrated backend now stores these records separately from online `games`.
An incoming history that extends the stored move prefix updates the board
session; divergent histories create a conflict record and leave the existing
session untouched.
