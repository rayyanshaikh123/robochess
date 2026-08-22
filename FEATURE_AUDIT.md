# RoboChess feature walkthrough

This is the current feature audit of the mobile app, FastAPI backend, and Pi
agent. “Working” means the UI action reaches an implemented code path; it does
not mean the required hardware or service is necessarily configured.

## Working flows

- Authentication: register, login, refresh, logout, profile loading, and
  profile display-name editing.
- Home: shows the active backend game position when available and links to the
  playable game flow when no game is active.
- Play: local chess moves, AI replies, move history, undo for backend games,
  analysis navigation, voice move input, board linking, camera preview, board
  validation, and automatic move detection when a configured camera/model is
  available.
- Analysis: loads a game report, reconstructs positions, navigates moves, and
  displays evaluation data.
- Puzzles: loads puzzle records from the backend, validates moves, advances the
  position, records attempts, and supports reset.
- Device management: link, select, inspect status, receive WebSocket updates,
  unlink, and refresh status.
- BLE local board: scan, connect, session start/reset/resume, state requests,
  move proposals, safe recovery undo, Wi-Fi provisioning, chunked messages,
  and ordered multi-move traffic.
- Learning: opening cards have lesson previews and practice actions; endgame
  and tactical cards now open usable lesson tracks with practice actions.
  Opening practice-start state is persisted locally per user/device.
- Pi calibration: manual calibration and contour-based automatic calibration
  are available through the local API.

## Honest limitations and remaining work

- Online matchmaking is not implemented in the backend. The Connect screen now
  starts the working game flow instead of showing a dead matchmaking button.
- OTA firmware updates are not implemented. The profile action is therefore a
  status refresh rather than a misleading update action.
- Opening lesson completion/mastery is not yet persisted. Opening data is a
  static curriculum, while cards truthfully show “READY” or “STARTED”.
- Pi undo rewinds the logical session and enters recovery, requiring the user to
  restore the physical pieces before resuming. It intentionally does not claim
  to reverse gantry motion automatically.
- Pi automatic calibration requires a camera frame containing a sufficiently
  clear board quadrilateral; it returns a useful 422 diagnostic when detection
  fails.
- Vision/engine features require a real camera, a trained model configured by
  `ROBOCHESS_MODEL_PATH`, and Stockfish. These are deployment prerequisites,
  not UI placeholders.

## Verification

- Backend tests: 5 passed.
- Pi tests: 29 passed.
- Synthetic Pi automatic-calibration test detected and ordered four corners.
- Flutter analyzer reports no compile errors; remaining findings are existing
  style, deprecation, and unused-code warnings.
