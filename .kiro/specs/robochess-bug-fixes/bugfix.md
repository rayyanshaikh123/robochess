# Bugfix Requirements Document

## Introduction

This document captures the requirements for fixing 10+ confirmed bugs across the RoboChess Flutter frontend. The bugs span four areas: Bluetooth board pairing (`ble_provision_screen.dart`, `board_link_screen.dart`), the Play game screen (`play_screen.dart`), the Learn platform (`learn_section.dart`, `openings_screen.dart`, `lesson_track_screen.dart`), and the Home Dashboard (`home_dashboard.dart`).

Each bug is described using the bug condition methodology: the condition that triggers the defect, the incorrect behavior that results, the correct behavior that should replace it, and the surrounding behavior that must be preserved (regression prevention).

---

## Bug Analysis

---

### BUG-1: BLE Scan Fails on First Tap (Race Condition)

**Summary:** The first tap on "Scan Nearby Boards" in `ble_provision_screen.dart` throws a bad-state error. FlutterBluePlus is not fully initialized or the adapter state has not yet been confirmed as `on` before `startScan` is called. The second tap succeeds because the adapter is by then fully ready.

### Current Behavior (Defect)

1.1 WHEN the user taps "Scan Nearby Boards" for the first time after opening `BleProvisionScreen` THEN the system throws a `StateError` (bad state) before any scan results appear

1.2 WHEN `_scan()` is called and `FlutterBluePlus.adapterState` has not yet emitted a confirmed `BluetoothAdapterState.on` THEN the system proceeds into `startScan` with an unready adapter and crashes

### Expected Behavior (Correct)

2.1 WHEN the user taps "Scan Nearby Boards" for the first time THEN the system SHALL await confirmation that the Bluetooth adapter state is `on` before calling `startScan`, and SHALL display a scanning indicator without error

2.2 WHEN `_scan()` is called and the adapter state is not yet confirmed THEN the system SHALL wait for the adapter to reach the `on` state (or timeout gracefully) before proceeding

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user taps "Scan" and Bluetooth is genuinely disabled THEN the system SHALL CONTINUE TO show a clear "Bluetooth is disabled" error message without crashing

3.2 WHEN the user taps "Scan" on a subsequent attempt after a successful first scan THEN the system SHALL CONTINUE TO cancel the previous scan subscription and start a fresh scan

---

### BUG-2: "Device Not Found" Error After Check Status

**Summary:** After tapping "Check Status" in `ble_provision_screen.dart`, a "Device not found" error is surfaced to the user. The provision flow reads `deviceId` from BLE advertisement data, but when attempting to look up a related secret or cloud record, the lookup uses the wrong identifier or an identifier that is not yet populated in the local device list.

### Current Behavior (Defect)

1.3 WHEN the user taps "Check Status" on a discovered board and the provision flow requests a network-status check THEN the system displays "Device not found" (or a similar lookup error) because it attempts to reference a device record that does not yet exist in the local store

1.4 WHEN `_provision()` calls `ref.read(deviceRepositoryProvider).onboardingToken(deviceId: deviceId)` before the device list has been loaded THEN the system throws an error that propagates as "Device not found" in the UI

### Expected Behavior (Correct)

2.3 WHEN the user taps "Check Status" on a discovered board THEN the system SHALL use the `deviceId` read directly from the BLE advertisement data (or from `connectAndReadDeviceId`) for all provisioning steps without requiring the device to be pre-registered in the local device list

2.4 WHEN `onboardingToken` is requested for a device not yet in the local store THEN the system SHALL accept a raw `deviceId` string and succeed, not require a prior `deviceListProvider` entry

### Unchanged Behavior (Regression Prevention)

3.3 WHEN the provision flow completes successfully THEN the system SHALL CONTINUE TO call `ref.read(deviceListProvider.notifier).load()` to refresh the linked boards list before navigating away

3.4 WHEN a BLE connection error occurs during provisioning THEN the system SHALL CONTINUE TO display the error message in the `_message` text field and reset `_working` to false

---

### BUG-3: Missing Back Button on Board Link Screen

**Summary:** `BoardLinkScreen` has an `AppBar` with a title but no `leading` back button. Users who navigate to `/connect/link` have no way to return to the previous screen without using the OS back gesture (which may not be available on all devices or form factors).

### Current Behavior (Defect)

1.5 WHEN the user navigates to the Board Link screen (`/connect/link`) THEN the system renders an `AppBar` with no back navigation affordance (no `leading` icon button)

1.6 WHEN the user wants to cancel board linking and return to the Connect screen THEN the system provides no visible UI control to do so

### Expected Behavior (Correct)

2.5 WHEN the Board Link screen is rendered THEN the system SHALL display a back arrow (`Icons.arrow_back`) in the `AppBar` leading position that calls `context.pop()` when tapped

2.6 WHEN the user taps the back arrow on the Board Link screen THEN the system SHALL navigate back to the previous route without error

### Unchanged Behavior (Regression Prevention)

3.5 WHEN the user is actively typing a pairing code and navigates back THEN the system SHALL CONTINUE TO dismiss the keyboard and clean up the `_codeCtrl` controller on dispose

3.6 WHEN the BLE scan button on the Board Link screen is tapped THEN the system SHALL CONTINUE TO push `/connect/ble` correctly

---

### BUG-4: STT Voice Input Is Inaccurate for Chess Notation

**Summary:** The speech-to-text pipeline in `play_screen.dart` passes raw transcription text directly to `parseMove()` without any chess-context post-processing. The move parser already handles phonetic variants (e.g. "delta four" → "d4"), but the STT engine on some devices returns unexpected tokenizations (e.g. "D2" as "D 2" vs "D2", or "eight" as "8" vs never emitting it). The vocabulary in `move_parser.dart` is a reasonable foundation but needs expansion for common mis-transcriptions.

### Current Behavior (Defect)

1.7 WHEN the user speaks a valid chess move such as "D2 to D4" THEN the system sometimes fails to recognize the move and shows an error like "Couldn't read a source square" because the STT result uses unexpected spacing, capitalization, or homophone substitutions not covered by the parser vocabulary

1.8 WHEN the STT engine returns a move token as two separate words (e.g. "g 7" instead of "g7") THEN the system fails to parse it even though the file and rank are individually present

1.9 WHEN the STT engine returns a file as a number-adjacent word (e.g. "be" for "b", "see" for "c", "to" as both a connector and a rank) THEN the system misinterprets the token because of vocabulary gaps or ambiguous double-mapping

### Expected Behavior (Correct)

2.7 WHEN the STT result contains adjacent file and rank tokens separated by a space (e.g. "g 7") THEN the system SHALL merge adjacent file/rank token pairs into a single square token before parsing

2.8 WHEN the STT result contains a common mis-transcription of a file letter (e.g. "be" for b, "eff" for f, "gee" or "ji" for g, "aitch" for h) THEN the system SHALL map those tokens to the correct file character and proceed with parsing

2.9 WHEN "to" appears between two squares (e.g. "d2 to d4") THEN the system SHALL treat "to" solely as a skip connector and SHALL NOT interpret it as rank "2"

### Unchanged Behavior (Regression Prevention)

3.7 WHEN the STT result is a recognized special command such as "undo", "resign", or "castle kingside" THEN the system SHALL CONTINUE TO handle those commands correctly without treating them as moves

3.8 WHEN a parsed move is illegal for the current board position THEN the system SHALL CONTINUE TO show the "not a legal move" error without attempting to apply the move to the board

---

### BUG-5: GoError Crash When Navigating Back From Analysis

**Summary:** In `play_screen.dart`, tapping "Analyze" navigates using `context.go('/analysis?game_id=$_linkedGameId')`. `go()` replaces the entire navigation stack rather than pushing onto it. When the user taps "Back" inside `AnalysisScreen`, it calls `context.pop()`, but since `go()` destroyed the prior stack entry, there is nothing left to pop — causing a `GoError: There is nothing to pop`.

### Current Behavior (Defect)

1.10 WHEN the user taps the "Analyze" button on the Play screen THEN the system navigates using `context.go('/analysis?...')`, which replaces the current navigation stack and destroys the Play screen route entry

1.11 WHEN the user then taps the back arrow in `AnalysisScreen` THEN the system throws `GoError: There is nothing to pop` because the Play route is no longer on the stack

### Expected Behavior (Correct)

2.10 WHEN the user taps the "Analyze" button on the Play screen THEN the system SHALL navigate using `context.push('/analysis?game_id=$_linkedGameId')` so that the Play screen remains on the navigation stack

2.11 WHEN the user taps the back arrow in `AnalysisScreen` after arriving from the Play screen THEN the system SHALL pop back to the Play screen without any `GoError`

### Unchanged Behavior (Regression Prevention)

3.9 WHEN the user navigates to the Analysis screen directly via the bottom navigation bar THEN the system SHALL CONTINUE TO display the Analysis screen correctly (the shell route is unaffected by this change)

3.10 WHEN the user navigates to Analysis from Play and the game analysis loads successfully THEN the system SHALL CONTINUE TO display the evaluation graph, move history, and AI insight without regression

---

### BUG-6: Draw Offer Button Not Disabled When Opponent Is a Bot

**Summary:** The `_GameControls` widget in `play_screen.dart` always renders both the "Resign" and "Offer Draw" buttons with no awareness of the game mode. Offering a draw to an AI opponent is semantically meaningless and should be hidden or disabled when `mode` is `human_vs_ai` or `phone_vs_board`.

### Current Behavior (Defect)

1.12 WHEN the user is playing a game with `mode == 'human_vs_ai'` or `mode == 'phone_vs_board'` THEN the system displays the "Draw" offer button in an enabled, tappable state even though there is no bot opponent capable of accepting a draw

### Expected Behavior (Correct)

2.12 WHEN the user is playing against the AI (mode is `human_vs_ai` or `phone_vs_board`) THEN the system SHALL disable or hide the "Draw" button so the user cannot trigger a draw offer against a bot

2.13 WHEN the user is playing a human-vs-human game (`mode == 'human_vs_human'`) THEN the system SHALL display the "Draw" button in an enabled state

### Unchanged Behavior (Regression Prevention)

3.11 WHEN the user is playing in human-vs-human mode THEN the system SHALL CONTINUE TO show the Draw button as an active control

3.12 WHEN the current game mode changes (e.g. a new game is started) THEN the system SHALL CONTINUE TO re-evaluate draw button availability based on the new mode without requiring a hot restart

---

### BUG-7: Resign Button Does Nothing

**Summary:** The `_ControlBtn` for "Resign" in `_GameControls` has `onTap` implicitly `null` (no handler is passed from `_GameControls` and `_ControlBtn` falls back to `onTap: null`). There is no `resign()` method in `GameController` or `GameRepository`, and no API call is wired up.

### Current Behavior (Defect)

1.13 WHEN the user taps the "Resign" button on the Play screen THEN the system does nothing — no visual feedback, no state change, no API call, and the game continues

1.14 WHEN the user intends to forfeit the current game THEN the system has no `resignGame()` method in `GameController`, `GameRepository`, or `GameRemoteDataSource` to call

### Expected Behavior (Correct)

2.14 WHEN the user taps the "Resign" button THEN the system SHALL show a confirmation dialog asking the user to confirm resignation

2.15 WHEN the user confirms resignation in the dialog THEN the system SHALL call the resign endpoint on the backend, update the local game status to indicate the player has resigned, and display a game-over message

2.16 WHEN the resign endpoint does not yet exist on the backend THEN the system SHALL gracefully handle the failure (show an error message) rather than silently doing nothing

### Unchanged Behavior (Regression Prevention)

3.13 WHEN the user dismisses the resign confirmation dialog without confirming THEN the system SHALL CONTINUE TO play normally with the game state unmodified

3.14 WHEN the game is already over (checkmate, stalemate, draw) THEN the system SHALL CONTINUE TO show the final state and the resign button SHALL be disabled

---

### BUG-8: Player Label Shows "PLAYER_ONE" Instead of Logged-In Username

**Summary:** The `_PlayerRow` widget in `play_screen.dart` hard-codes the string `'PLAYER_ONE'` as the player display name. The authenticated user's display name is available via `userProfileProvider` (which returns a `UserProfile` with a `displayName` field) but is never read in this context.

### Current Behavior (Defect)

1.15 WHEN a logged-in user views the Play screen THEN the system displays the static string "PLAYER_ONE" as the player name instead of the user's actual display name

1.16 WHEN `userProfileProvider` resolves successfully with a `UserProfile` containing a non-empty `displayName` THEN the system does not use that value anywhere in `_PlayerRow`

### Expected Behavior (Correct)

2.17 WHEN the Play screen is rendered and `userProfileProvider` has resolved successfully THEN the system SHALL display the authenticated user's `displayName` in `_PlayerRow` in place of the hard-coded "PLAYER_ONE" string

2.18 WHEN `userProfileProvider` is still loading or has errored THEN the system SHALL display a sensible fallback (e.g. "Player" or the user's email prefix) rather than a hard-coded placeholder

### Unchanged Behavior (Regression Prevention)

3.15 WHEN the AI player row is rendered THEN the system SHALL CONTINUE TO display "AI LEVEL 8" (or the actual configured difficulty level) as the opponent name, unaffected by this change

3.16 WHEN the user navigates away and back to the Play screen THEN the system SHALL CONTINUE TO show the correct display name without needing to re-fetch

---

### BUG-9: Opening Selection Redirects to Play Tab Without Starting a Guided Lesson

**Summary:** In `_OpeningCard._openLesson()`, tapping "Practice This Opening" calls `context.go('/play')` after marking the opening as started. This navigates to the Play tab's root but performs no lesson initialization — no pre-loaded FEN for the opening, no move-by-move guidance, and no reference to which opening was selected. The old game state from any previous session may still be active.

### Current Behavior (Defect)

1.17 WHEN the user selects an opening in `OpeningsScreen` and taps "Practice This Opening" THEN the system navigates to `/play` but passes no opening context, resulting in a blank new-game screen with no guided lesson

1.18 WHEN the user arrives at the Play screen from an opening card THEN the system does not pre-load the opening's starting position, does not display move-by-move instructions, and does not distinguish this session from a regular unguided game

### Expected Behavior (Correct)

2.19 WHEN the user taps "Practice This Opening" on an opening card THEN the system SHALL navigate to the Play screen with the opening's PGN notation passed as a route parameter or shared state, so the Play screen can set up the opening position

2.20 WHEN the Play screen receives an opening context THEN the system SHALL load the opening's starting position into the chess engine, display the expected move sequence as a hint panel, and guide the user through the opening moves one at a time

### Unchanged Behavior (Regression Prevention)

3.17 WHEN the user starts a regular new game from the Play screen without an opening context THEN the system SHALL CONTINUE TO start from the standard initial position with no lesson overlay

3.18 WHEN the opening lesson is active and the user makes the correct next move in the opening line THEN the system SHALL CONTINUE TO advance to the next move hint without disrupting the game logic

---

### BUG-10: Learn Platform Is Non-Functional (Lesson Flow Never Initialized)

**Summary:** The entire lesson track flow — `LessonTrackScreen`, `OpeningsScreen`, and the `_CategoryCard` in `learn_section.dart` — directs users to static pages or the Play tab. No lesson content is loaded, no opening moves are replayed interactively, and no progress is persisted beyond a simple "started" flag stored in `FlutterSecureStorage`. The "CONTINUE LESSON" FAB also always goes to `/learn/openings` regardless of which track was last active.

### Current Behavior (Defect)

1.19 WHEN the user taps a lesson card in `LessonTrackScreen` and taps "PRACTICE" THEN the system calls `context.go('/play')` with no lesson context, resulting in a bare Play screen with no lesson guidance

1.20 WHEN the user taps "CONTINUE LESSON" on the Learn section FAB THEN the system always navigates to `/learn/openings` regardless of which category or lesson was last active

1.21 WHEN any lesson or opening is "started" THEN the system marks it started in secure storage but never records progress beyond that binary flag — there is no move counter, completion state, or resumption point

### Expected Behavior (Correct)

2.21 WHEN the user taps "PRACTICE" on a lesson card in `LessonTrackScreen` THEN the system SHALL pass the lesson's objective and associated opening/tactic context to the Play screen so a guided session can begin

2.22 WHEN the "CONTINUE LESSON" FAB is tapped THEN the system SHALL navigate to the most recently active lesson track (stored in persistent state), not hard-code `/learn/openings`

2.23 WHEN a lesson is in progress THEN the system SHALL track which moves have been completed and persist that progress so the user can resume where they left off

### Unchanged Behavior (Regression Prevention)

3.19 WHEN the user has never started any lesson THEN the system SHALL CONTINUE TO show the default Learn section hero and category grid without error

3.20 WHEN the user navigates to the Learn section from the bottom nav after completing a lesson THEN the system SHALL CONTINUE TO show updated progress indicators reflecting completed lessons

---

### BUG-11: Home Dashboard Shows Only Static / Hardcoded Content

**Summary:** `HomeDashboard` only reads `gameControllerProvider` to show the last game's board position. It hard-codes the initial board position when no game is active and provides no live stats, no recent game history, no quick-action shortcuts, and no meaningful data from the backend. The `userStatsProvider` and `userProfileProvider` from `user_provider.dart` exist but are not consumed anywhere in the dashboard.

### Current Behavior (Defect)

1.22 WHEN the user navigates to the Home Dashboard THEN the system displays only a static chess board (initial position or last FEN from `gameControllerProvider`) with a "Start a Game" button — no stats, no recent games, no user-specific data

1.23 WHEN `userProfileProvider` and `userStatsProvider` have resolved successfully with real backend data THEN the system does not use that data anywhere on the Home Dashboard

### Expected Behavior (Correct)

2.24 WHEN the Home Dashboard is rendered and `userProfileProvider` has resolved THEN the system SHALL display the authenticated user's display name and a personalized greeting

2.25 WHEN the Home Dashboard is rendered and `userStatsProvider` has resolved THEN the system SHALL display at minimum the user's total games played and win/loss record

2.26 WHEN a linked game exists in `gameControllerProvider` THEN the system SHALL display the live board position with a "Resume Game" quick-action button in addition to "New Game"

### Unchanged Behavior (Regression Prevention)

3.21 WHEN `userProfileProvider` or `userStatsProvider` is still loading THEN the system SHALL CONTINUE TO render the board section without crashing, showing a loading skeleton for the stats area

3.22 WHEN no game is active THEN the system SHALL CONTINUE TO show the initial board position and the "Start a Game" button as before

---

## Bug Condition Summary

The following table maps each bug to its formal condition, showing what inputs trigger the defect and what the fix must preserve.

| Bug | Condition C(X) — triggers bug | Fix: F'(X) must satisfy | Preserve: F(X) for ¬C(X) |
|-----|-------------------------------|--------------------------|---------------------------|
| BUG-1 | First scan call before adapter confirmed ready | Await adapter state before startScan | Subsequent scans, disabled-BT error |
| BUG-2 | Check Status called before device in local store | Use raw deviceId from BLE advertisement | Successful provision, error display |
| BUG-3 | User opens BoardLinkScreen | Render back arrow in AppBar leading | Code entry, BLE push, form submission |
| BUG-4 | STT returns spaced tokens or unhandled homophones | Merge tokens, expand vocabulary | Legal commands, illegal move errors |
| BUG-5 | User navigates to Analysis via context.go() | Use context.push() from Play screen | Bottom-nav Analysis route, data load |
| BUG-6 | Game mode is human_vs_ai or phone_vs_board | Disable/hide Draw button | Draw button active for hvh mode |
| BUG-7 | User taps Resign button | Show confirm dialog, call resign API | Dismiss dialog, post-game state |
| BUG-8 | Play screen rendered with logged-in user | Read userProfileProvider for display name | AI row label, name on re-navigation |
| BUG-9 | User taps "Practice This Opening" | Pass opening context to Play screen | Regular new game without context |
| BUG-10 | User taps "PRACTICE" on lesson card | Pass lesson context, track progress | Default Learn view, no-lesson play |
| BUG-11 | Home Dashboard rendered | Consume userProfileProvider, userStatsProvider | Board render on loading/no-game state |
| BUG-12 | App launched with no runtime URL saved and USB cable absent | Read persisted URL from SecureStorage; fall back to compile-time default | --dart-define workflow, token storage, all authenticated API calls |

```pascal
// Formal Bug Condition Functions

FUNCTION isBleFirstScanRace(X)
  INPUT: X = { adapterStateConfirmed: bool, tapCount: int }
  RETURN X.tapCount == 1 AND NOT X.adapterStateConfirmed
END FUNCTION

FUNCTION isDeviceNotFound(X)
  INPUT: X = { deviceInLocalStore: bool, provisionStep: String }
  RETURN X.provisionStep == 'checkStatus' AND NOT X.deviceInLocalStore
END FUNCTION

FUNCTION isMissingBackButton(X)
  INPUT: X = { screen: String }
  RETURN X.screen == 'BoardLinkScreen'
END FUNCTION

FUNCTION isSTTAmbiguous(X)
  INPUT: X = { tokens: List<String> }
  RETURN tokens.any(t => isSpacedSquarePair(t) OR isUnhandledHomophone(t))
END FUNCTION

FUNCTION isGoErrorCrash(X)
  INPUT: X = { navigationType: String, currentRoute: String }
  RETURN X.navigationType == 'go' AND X.currentRoute == '/analysis'
END FUNCTION

FUNCTION isDrawButtonShownVsBot(X)
  INPUT: X = { gameMode: String }
  RETURN X.gameMode == 'human_vs_ai' OR X.gameMode == 'phone_vs_board'
END FUNCTION

FUNCTION isResignNoOp(X)
  INPUT: X = { buttonTapped: String, handlerAssigned: bool }
  RETURN X.buttonTapped == 'resign' AND NOT X.handlerAssigned
END FUNCTION

FUNCTION isHardcodedPlayerName(X)
  INPUT: X = { playerNameSource: String }
  RETURN X.playerNameSource == 'hardcoded'
END FUNCTION

FUNCTION isOpeningNoContext(X)
  INPUT: X = { navigationType: String, openingContext: bool }
  RETURN X.navigationType == 'go(/play)' AND NOT X.openingContext
END FUNCTION

FUNCTION isStaticDashboard(X)
  INPUT: X = { dataSourcesUsed: List<String> }
  RETURN NOT X.dataSourcesUsed.contains('userProfileProvider')
     AND NOT X.dataSourcesUsed.contains('userStatsProvider')
END FUNCTION

FUNCTION isHardcodedServerUrl(X)
  INPUT: X = { runtimeUrlSaved: bool, networkReachable: bool }
  OUTPUT: boolean

  // Bug fires when there is no persisted override and the hardcoded IP is unreachable
  RETURN NOT X.runtimeUrlSaved AND NOT X.networkReachable
END FUNCTION

// Fix Checking — BUG-12
FOR ALL X WHERE isHardcodedServerUrl(X) DO
  resolvedUrl ← resolveServerUrl'(X)
  ASSERT resolvedUrl != 'http://172.20.10.3:8000'
     AND resolvedUrl IS validHttpUrl
END FOR

// Preservation Goal (applies to all bugs)
FOR ALL X WHERE NOT isBugCondition(X) DO
  ASSERT F(X) = F'(X)  // unchanged behavior for non-buggy inputs
END FOR
```

---

### BUG-12: App Completely Unusable Without USB Cable (Hardcoded Tethering IP)

**Summary:** `AppConfig.apiBaseUrl` and `AppConfig.wsBaseUrl` default to `172.20.10.3`, the Mac's IP on the iPhone's USB-tethering network. `String.fromEnvironment` is resolved at compile time, so these values cannot be changed at runtime. When the USB cable is removed — or the user is on any other network — every API call (including login) throws a `SocketException` or `TimeoutException`, making the app completely unusable. The fix introduces a `ServerConfigStore` that persists a runtime-configurable URL in `FlutterSecureStorage`, exposes it via a Riverpod provider, and rebuilds `ApiClient`/`GameSocketClient` when the URL changes. A "Configure server" affordance on the login screen lets users set the URL before attempting to connect.

### Current Behavior (Defect)

1.24 WHEN the app is launched on a network where `172.20.10.3` is not reachable (no USB cable, different WiFi, etc.) THEN every API call throws a `SocketException` or `TimeoutException`, the login screen displays an error, and no part of the app is functional

1.25 WHEN `apiClientProvider` and `gameSocketProvider` are constructed THEN the system reads `AppConfig.apiBaseUrl` / `AppConfig.wsBaseUrl` which are compile-time constants; there is no way to supply a different URL at runtime without rebuilding the app with `--dart-define`

1.26 WHEN a user on a different network wants to change the backend URL THEN the system provides no UI mechanism to do so — the URL is invisible to the user and only changeable by a developer with access to the build toolchain

### Expected Behavior (Correct)

2.27 WHEN the app is launched and a runtime server URL has previously been saved THEN the system SHALL read that URL from `FlutterSecureStorage` and use it for all `ApiClient` and `GameSocketClient` construction in place of the compile-time default

2.28 WHEN no runtime URL has been saved THEN the system SHALL fall back to the compile-time `AppConfig.apiBaseUrl` / `AppConfig.wsBaseUrl` values, preserving the existing developer `--dart-define` workflow unchanged

2.29 WHEN the user updates the server URL via the in-app settings affordance THEN the system SHALL persist the new URL to `FlutterSecureStorage`, invalidate the current `apiClientProvider` and `gameSocketProvider`, and reconstruct those providers with the new URL so subsequent API calls use it without requiring an app restart

2.30 WHEN the login screen is rendered THEN the system SHALL display a "Configure server" link or icon that opens a dialog or sub-screen where the user can view and edit the current backend URL before attempting to log in

2.31 WHEN the user saves a new server URL in the configure-server dialog THEN the system SHALL validate that the value is a non-empty, syntactically valid HTTP/HTTPS URL before persisting it, and SHALL show an inline error if validation fails

### Unchanged Behavior (Regression Prevention)

3.23 WHEN the app is built with `--dart-define=API_BASE_URL=http://...` and no runtime URL override has been saved THEN the system SHALL CONTINUE TO use the `--dart-define` value exactly as today, with no behaviour change for the developer workflow

3.24 WHEN the user is already authenticated and a valid backend is reachable THEN the system SHALL CONTINUE TO perform login, registration, game creation, and WebSocket connections correctly, with no regression from the URL-resolution change

3.25 WHEN `TokenStore` reads or writes authentication tokens THEN the system SHALL CONTINUE TO use the same `FlutterSecureStorage` keys as before; the new `ServerConfigStore` SHALL use a distinct key (e.g. `server_base_url`) that does not collide with existing token keys

---
