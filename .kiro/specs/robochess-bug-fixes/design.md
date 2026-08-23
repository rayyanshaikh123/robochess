# RoboChess Bug Fixes – Design

## Overview

This document describes the fix approach for 11 confirmed bugs across the RoboChess Flutter frontend. The bugs span four areas:

- **BLE / Board Pairing** (BUG-1, BUG-2, BUG-3) – `ble_provision_screen.dart`, `board_link_screen.dart`
- **Play Screen** (BUG-4, BUG-5, BUG-6, BUG-7, BUG-8) – `play_screen.dart`, `move_parser.dart`
- **Learn Platform** (BUG-9, BUG-10) – `openings_screen.dart`, `learn_section.dart`, `lesson_track_screen.dart`
- **Home Dashboard** (BUG-11) – `home_dashboard.dart`

Each fix is minimal and targeted. The strategy is to make the smallest code change that satisfies the bug condition while leaving all non-buggy paths intact (Preservation). Fixes that require new API methods (BUG-7 resign) are designed to fail gracefully when the backend endpoint is absent.

---

## Glossary

- **Bug_Condition (C)**: The specific input or state combination that reliably triggers the defect.
- **Property (P)**: The correct observable outcome that must hold when the bug condition is true and the fix is applied.
- **Preservation**: All observable behaviors that exist for inputs where the bug condition is false; these must be byte-for-byte identical before and after the fix.
- **F**: The original (unfixed) function or widget.
- **F'**: The fixed function or widget.
- **isBugCondition(X)**: Pseudocode predicate returning `true` when input X falls in the buggy input domain.
- **adapterState.first**: The first value emitted by `FlutterBluePlus.adapterState` — may be stale on first call if the stream has not yet emitted a fresh value.
- **`_rankMap` / `_skipWords`**: Vocabulary tables in `move_parser.dart`. `'to'` appears in both, creating an ambiguity when it follows a file token.
- **`context.go()` vs `context.push()`**: `go_router` methods. `go()` replaces the entire navigation stack; `push()` adds to it and allows `pop()`.
- **`userProfileProvider` / `userStatsProvider`**: Riverpod `FutureProvider`s in `user_provider.dart` that expose live backend data for the authenticated user.
- **`_gameMode`**: The game mode string (`'human_vs_ai'`, `'phone_vs_board'`, `'human_vs_human'`) stored in `_PlayScreenState` after a game is created.
- **OpeningContext**: A lightweight data class (`name: String`, `pgn: String`) carried as a `go_router` route `extra` from the Learn platform to the Play screen to enable guided opening practice.

---

## Bug Details

### BUG-1 – BLE Scan Race Condition (ble_provision_screen.dart)

The `scan()` method in `robochess_ble.dart` guards with `await FlutterBluePlus.adapterState.first`. On Android, `.first` resolves to the most recently cached stream value, which may still be `unknown` or `turningOn` on the first call even if Bluetooth is physically on. The second tap works because by then the stream has emitted `on`. The fix awaits the adapter stream until `on` is emitted (with a short timeout so a genuinely-disabled adapter still errors out quickly).

**Formal Specification:**

```
FUNCTION isBleFirstScanRace(X)
  INPUT: X = { adapterEmittedOnState: bool, tapCount: int }
  OUTPUT: boolean

  RETURN X.tapCount == 1
         AND NOT X.adapterEmittedOnState
END FUNCTION
```

**Examples:**
- Tap 1, adapter stream at `unknown` → throws `StateError("Bluetooth is disabled...")` — **bug**
- Tap 2, adapter stream now at `on` → scan starts normally — working
- Tap 1, adapter genuinely off → must still show "Bluetooth is disabled" — **preserved**

---

### BUG-2 – Device Not Found After Check Status (ble_provision_screen.dart)

`_provision()` calls `onboardingToken(deviceId: deviceId)` with the raw BLE device ID. The bug surfaces if `DeviceRepository.onboardingToken()` or its underlying data source makes a prior local-store lookup that fails because the device has not yet been registered. The fix ensures that all provisioning steps use the raw `deviceId` from `connectAndReadDeviceId()` directly and that `onboardingToken` is a pure network call with no local-store precondition.

**Formal Specification:**

```
FUNCTION isDeviceNotFoundBug(X)
  INPUT: X = { deviceInLocalStore: bool, provisionStep: String }
  OUTPUT: boolean

  RETURN X.provisionStep IN ['checkStatus', 'onboardingToken']
         AND NOT X.deviceInLocalStore
END FUNCTION
```

**Examples:**
- New board, never linked before, tap "Check Status" → "Device not found" — **bug**
- Board already in local device list, tap "Check Status" → succeeds — working
- Successful provision flow followed by `deviceListProvider.notifier.load()` — **preserved**

---

### BUG-3 – Missing Back Button on Board Link Screen (board_link_screen.dart)

`BoardLinkScreen.build()` constructs an `AppBar` with a `title` but no `leading` parameter. Flutter does not automatically supply a back button for screens reached via `context.push()` inside a `StatefulShellRoute`. The fix adds `leading: IconButton(icon: const Icon(Icons.arrow_back, color: kPrimary), onPressed: () => context.pop())` to the `AppBar`.

**Formal Specification:**

```
FUNCTION isMissingBackButton(X)
  INPUT: X = { screen: String, hasLeading: bool }
  OUTPUT: boolean

  RETURN X.screen == 'BoardLinkScreen' AND NOT X.hasLeading
END FUNCTION
```

**Examples:**
- Navigate to `/connect/link` → AppBar shows no back arrow — **bug**
- After fix, AppBar shows back arrow, tap returns to `/connect` — correct

---

### BUG-4 – STT Token Ambiguity in Move Parser (move_parser.dart)

Two separate sub-bugs share the same root:

**Sub-bug A – `'to'` treated as rank `'2'`:** `_rankMap` maps `'to' → '2'`. Inside `_parseSquare`, after matching a file token, the code checks `_rankMap.containsKey(tokens[idx + 1])` and finds `'to'` → maps it to rank `'2'`. So `"d to d4"` is parsed as source square `d2` (correct by accident) but `"e to e4"` produces `e2` and the connector `"to"` is consumed as the rank, leaving the destination unreadable.

**Sub-bug B – Spaced file/rank tokens:** If the STT engine emits `"g 7"` as two tokens `["g", "7"]`, the `_parseSquare` function correctly handles it because it checks `_fileMap[tok]` and then `_rankMap[tokens[idx+1]]`. However, if the rank is `"to"` the rank `'2'` is spuriously assigned (Sub-bug A). The real gap is the skip-word `"to"` not being excluded from the rank check inside `_parseSquare` when we want it as a connector.

The fix: Inside `_parseSquare`, when consuming a two-token file+rank pair, explicitly exclude tokens that appear in `_skipWords` from being treated as a rank. Add the constant set `_ambiguousRankWords = {'to', 'too', 'for'}` (words that are both connectors and ranks) and skip them as ranks inside `_parseSquare`.

Additionally, expand `_fileMap` with `'be' → 'b'` and `'ji' → 'g'` / `'jee' → 'g'` (already present for `'ji'`/`'jee'`).

**Formal Specification:**

```
FUNCTION isSTTAmbiguous(X)
  INPUT: X = { tokens: List<String> }
  OUTPUT: boolean

  RETURN tokens.any(t =>
      (isFileToken(tokens[i]) AND tokens[i+1] IN _ambiguousRankWords)
      OR (isUnhandledHomophone(t))
  )
END FUNCTION
```

**Examples:**
- `"d to d4"` → `_parseSquare` reads `d` + `to` → currently `d2`, connector consumed — **bug**
- After fix, `"d to d4"` → `_parseSquare` reads `d` only (skips `to`), skip loop skips `to`, reads destination `d4` — correct
- `"g 7"` → `_parseSquare` reads `g` + `7` → `g7` — already works
- `"undo"` → `MoveParseResult.command('UNDO')` — **preserved**
- Illegal move → `MoveParseResult.failure(...)` — **preserved**

---

### BUG-5 – GoError When Navigating Back From Analysis (play_screen.dart)

`_GameControls.onAnalyze` calls `context.go('/analysis?game_id=$_linkedGameId')`. `go_router`'s `go()` replaces the entire navigation stack. When `AnalysisScreen` calls `context.pop()`, there is no prior entry on the stack to return to, causing `GoError: There is nothing to pop`.

The fix: Replace `context.go(...)` with `context.push(...)` in the Play screen. The Analysis screen's existing `context.pop()` back button then works correctly.

**Formal Specification:**

```
FUNCTION isGoErrorCrash(X)
  INPUT: X = { navigationType: String, destination: String }
  OUTPUT: boolean

  RETURN X.navigationType == 'go'
         AND X.destination STARTS_WITH '/analysis'
END FUNCTION
```

**Examples:**
- Tap "Analyze" → `context.go('/analysis?...')` → tap back in Analysis → `GoError` — **bug**
- After fix, `context.push('/analysis?...')` → tap back → returns to Play — correct
- Navigate to Analysis via bottom nav tab → shell route unaffected — **preserved**

---

### BUG-6 – Draw Button Shown When Playing Against Bot (play_screen.dart)

`_GameControls` always renders the Draw button in an enabled state. It has no knowledge of the game mode. The play screen knows the mode from `_PreGameResult.mode` but never stores it in widget state or passes it to `_GameControls`.

The fix:
1. Add `String _gameMode = 'human_vs_ai'` to `_PlayScreenState`, set it from `result.mode` inside `_startGameFlow`.
2. Pass `gameMode: _gameMode` to `_GameControls`.
3. In `_GameControls`, add `final String gameMode` parameter. Hide/disable the Draw button when `gameMode != 'human_vs_human'`.

**Formal Specification:**

```
FUNCTION isDrawButtonShownVsBot(X)
  INPUT: X = { gameMode: String, drawButtonEnabled: bool }
  OUTPUT: boolean

  RETURN X.gameMode IN ['human_vs_ai', 'phone_vs_board']
         AND X.drawButtonEnabled
END FUNCTION
```

**Examples:**
- `mode = 'human_vs_ai'` → Draw button visible and tappable — **bug**
- After fix, Draw button hidden for bot modes — correct
- `mode = 'human_vs_human'` → Draw button shown — **preserved**

---

### BUG-7 – Resign Button Does Nothing (play_screen.dart + game layer)

`_GameControls` accepts `onUndo` and `onAnalyze` callbacks but no `onResign`. The "Resign" `_ControlBtn` therefore has `onTap: null` implicitly. There is also no `resignGame()` method anywhere in the game stack (`GameController`, `GameRepository`, `GameRemoteDataSource`).

The fix has three parts:
1. Add `onResign: VoidCallback?` to `_GameControls` and wire it to the "Resign" button.
2. In `_PlayScreenState`, implement `_resignGame()`: show a `showDialog` confirmation, then call `ref.read(gameControllerProvider.notifier).resignGame()` on confirm.
3. Add `resignGame()` to `GameController`, `GameRepository`, and `GameRemoteDataSource` (POST `/games/{gameId}/resign`). Handle 404/network failure gracefully with a `setState(() => _syncError = ...)` rather than a crash.

**Formal Specification:**

```
FUNCTION isResignNoOp(X)
  INPUT: X = { buttonTapped: String, resignHandlerAssigned: bool }
  OUTPUT: boolean

  RETURN X.buttonTapped == 'resign' AND NOT X.resignHandlerAssigned
END FUNCTION
```

**Examples:**
- Tap Resign → nothing happens — **bug**
- After fix, tap Resign → confirmation dialog shown — correct
- Confirm resign → backend called, game-over state shown — correct
- Cancel dialog → game continues unmodified — **preserved**
- Game already over → Resign button disabled — **preserved**

---

### BUG-8 – Player Label Shows Hard-Coded String (play_screen.dart)

`_PlayerRow` hard-codes the string `'PLAYER_ONE'`. It is a `StatelessWidget` receiving only `chess.Chess game`. `userProfileProvider` is available in `user_provider.dart` but never referenced from this widget.

The fix: Convert `_PlayerRow` to a `ConsumerWidget`. Read `ref.watch(userProfileProvider)`. Use `profile.valueOrNull?.displayName ?? 'Player'` as the display name. This requires `_PlayerRow` to be inside the Riverpod widget tree (it already is via `PlayScreen`).

**Formal Specification:**

```
FUNCTION isHardcodedPlayerName(X)
  INPUT: X = { playerNameSource: String }
  OUTPUT: boolean

  RETURN X.playerNameSource == 'hardcoded_literal'
END FUNCTION
```

**Examples:**
- Logged-in user "Magnus" → shows "PLAYER_ONE" — **bug**
- After fix, shows "MAGNUS" (or display name) — correct
- AI player row still shows "AI LEVEL 8" — **preserved**

---

### BUG-9 – Opening Selection Goes to Bare Play Tab (openings_screen.dart + play_screen.dart)

`_OpeningCard._openLesson()` calls `context.go('/play')` with no data. The Play screen receives no opening context, starts from the default initial position, and provides no guided lesson. The old game state from any previous session may still be shown.

The fix:
1. Define an `OpeningContext` data class (`name`, `pgn`) in `domain/models/`.
2. In `_openLesson()`, change `context.go('/play')` to `context.go('/play', extra: OpeningContext(name: opening.name, pgn: opening.notation))`.
3. In `PlayScreen.initState()` (or `build()`), read `GoRouterState.of(context).extra as OpeningContext?`. If non-null, load the opening position into `_game` via `_game.load_pgn(openingContext.pgn)` and set a `_openingContext` state variable.
4. Show a collapsible hint banner in `_buildChessBoard` context when `_openingContext != null`, displaying the expected next move from the opening line.

**Formal Specification:**

```
FUNCTION isOpeningNoContext(X)
  INPUT: X = { navigationType: String, extraPassed: bool }
  OUTPUT: boolean

  RETURN X.navigationType == 'go(/play)'
         AND NOT X.extraPassed
END FUNCTION
```

**Examples:**
- Tap "Practice This Opening" → `/play` with no context → blank game — **bug**
- After fix, `/play` with `OpeningContext(name, pgn)` → position loaded, hint shown — correct
- New game started from Play screen directly (no extra) → normal game — **preserved**

---

### BUG-10 – Learn Platform Lesson Flow Never Initialized (learn_section.dart + lesson_track_screen.dart)

`LessonTrackScreen` lesson cards call `context.go('/play')` with no lesson context (same root cause as BUG-9). Additionally, the "CONTINUE LESSON" FAB in `learn_section.dart` always pushes `/learn/openings` regardless of the last active track.

The fix:
1. Lesson cards in `LessonTrackScreen` pass `extra: OpeningContext(name: lesson.title, pgn: lesson.objective)` (or a dedicated `LessonContext`) when navigating to `/play`, enabling the Play screen guided mode (reuses BUG-9 fix).
2. Persist the last-visited lesson track route key (e.g. `'/learn/openings'`, `'/learn/endgames'`, `'/learn/tactics'`) to `FlutterSecureStorage` with key `'last_lesson_route'` whenever a category card is tapped.
3. `_ContinueFAB` reads the persisted key via `flutter_secure_storage` and navigates to that route (fallback: `'/learn/openings'`).

**Formal Specification:**

```
FUNCTION isLessonFlowNeverInitialized(X)
  INPUT: X = { lessonNavExtra: bool, continueFabTarget: String }
  OUTPUT: boolean

  RETURN NOT X.lessonNavExtra
      OR X.continueFabTarget == 'hardcoded:/learn/openings'
END FUNCTION
```

**Examples:**
- Tap PRACTICE in LessonTrackScreen → `/play` with no context — **bug**
- CONTINUE FAB always → `/learn/openings` regardless of last track — **bug**
- After fix, PRACTICE passes lesson context; CONTINUE goes to last track — correct
- No lesson ever started → CONTINUE FAB defaults to `/learn/openings` — **preserved**

---

### BUG-11 – Home Dashboard Shows Only Static Content (home_dashboard.dart)

`HomeDashboard.build()` reads only `gameControllerProvider`. `userProfileProvider` and `userStatsProvider` exist in `user_provider.dart` but are never consumed. The screen shows a static board and no user-specific data.

The fix: In `HomeDashboard.build()`, also `ref.watch(userProfileProvider)` and `ref.watch(userStatsProvider)`. Render a greeting with the user's display name, a stats row (games played, win/loss), and a "Resume Game" button when a live game exists. Use `AsyncValue.when(data:, loading:, error:)` to show loading skeletons without crashing.

**Formal Specification:**

```
FUNCTION isStaticDashboard(X)
  INPUT: X = { dataSourcesConsumed: List<String> }
  OUTPUT: boolean

  RETURN NOT X.dataSourcesConsumed.contains('userProfileProvider')
      AND NOT X.dataSourcesConsumed.contains('userStatsProvider')
END FUNCTION
```

**Examples:**
- Dashboard renders → shows only board, no user name or stats — **bug**
- After fix, shows greeting with display name and win/loss stats — correct
- `userProfileProvider` still loading → loading skeleton shown, no crash — **preserved**
- No active game → "Start a Game" button shown — **preserved**

---

## Expected Behavior

### Preservation Requirements

The following behaviors must be identical before and after all fixes:

**BLE / Pairing**
- Subsequent BLE scans (tap 2+) continue to cancel the previous subscription and start fresh.
- When Bluetooth is genuinely disabled, the existing `StateError` message "Bluetooth is disabled" continues to surface in the UI.
- Successful provision flow continues to call `deviceListProvider.notifier.load()` before navigating to `/connect`.

**Play Screen**
- All legal board tap interactions, move highlighting, and move history updates are unaffected.
- WebSocket game sync, auto-detect board loop, and snapshot capture flows are unaffected.
- Voice command special words (`undo`, `resign`, `castle kingside`) continue to work.
- Illegal move attempts continue to surface a user-visible error without applying the move.
- The Analysis screen reached via the bottom nav shell route continues to work independently.
- In human-vs-human mode, the Draw button remains visible and enabled.
- When a game is over, Resign button is disabled.
- The AI player row label continues to show the configured engine level.

**Learn Platform**
- The default Learn section hero and category grid render correctly when no lesson has ever been started.
- Puzzle Vault load, solve navigation, and refresh continue to work.
- Openings search/filter/mini-board all continue to work.
- `_startedOpenings` persistence in `FlutterSecureStorage` continues to function.

**Home Dashboard**
- The chess board continues to render (initial position when no game, live FEN when active).
- "Start a Game" button navigation to `/play` continues to work.

---

## Hypothesized Root Causes

1. **BUG-1 – Adapter state stream cold start**: `adapterState.first` resolves immediately to the last-emitted cached value of the `BehaviorSubject`-like stream, which may be `unknown` before the Bluetooth stack has initialised. Using `.firstWhere((state) => state == BluetoothAdapterState.on).timeout(...)` waits for a fresh confirmed value.

2. **BUG-2 – Possible local store precondition in DeviceRepository**: The `onboardingToken()` data source call may route through a method that pre-checks the local device list (a defensive pattern elsewhere in the repo). The raw `deviceId` from BLE advertisement should be sufficient; the fix verifies no local-store lookup precedes the network call.

3. **BUG-3 – Missing `leading:` in AppBar constructor**: Flutter's `AppBar` does not inject a back button automatically in screens reached by `context.push()` inside a `StatefulShellRoute`. The fix is a one-line constructor change.

4. **BUG-4 – Vocabulary collision in `_rankMap` / `_skipWords`**: `'to'` is listed in both maps. `_parseSquare` checks `_rankMap` before the skip loop runs, so `'to'` after a file is consumed as rank `'2'` instead of being left as a connector for the skip loop. The fix adds an exclusion set checked inside `_parseSquare`.

5. **BUG-5 – `go()` vs `push()` semantic mismatch**: `go()` is a full stack replacement, appropriate for tab-level navigation. Using it for a detail screen (Analysis) that has a back button is the direct cause. `push()` is the correct primitive.

6. **BUG-6 – Mode information not threaded to `_GameControls`**: The game mode is created inside `_startGameFlow` and stored in `_PreGameResult` but never persisted to widget state or passed down to `_GameControls`. The fix adds a `_gameMode` field and passes it through.

7. **BUG-7 – Resign handler never wired**: `_GameControls` was built with two callbacks; a third for resign was never added. No API method exists. Both gaps must be filled together.

8. **BUG-8 – `_PlayerRow` isolated from Riverpod tree**: The widget was written as a pure `StatelessWidget` taking only `chess.Chess`. It never queries any provider. Converting to `ConsumerWidget` and reading `userProfileProvider` is the minimal fix.

9. **BUG-9/10 – Missing route `extra` parameter**: The `go_router` `extra` mechanism was available but not used when navigating to `/play`. The lesson and opening screens simply called `context.go('/play')` with no data attached.

10. **BUG-11 – Providers available but not consumed**: `userProfileProvider` and `userStatsProvider` were added to `user_provider.dart` but `HomeDashboard` was never updated to read them.

---

## Correctness Properties

Property 1: Bug Condition – BLE Adapter Ready Before Scan

_For any_ invocation of `_scan()` where `FlutterBluePlus.adapterState` has not yet emitted `BluetoothAdapterState.on`, the fixed `scan()` SHALL await that state (up to a 5-second timeout) before calling `startScan`, and SHALL NOT throw a `StateError` for a scan race condition.

**Validates: Requirements 2.1, 2.2**

---

Property 2: Preservation – BLE Disabled Error and Subsequent Scans

_For any_ invocation of `_scan()` where the adapter is genuinely disabled (never reaches `on` within timeout) OR for any subsequent scan (tapCount > 1), the fixed `scan()` SHALL produce exactly the same behavior as the original — either showing the "Bluetooth is disabled" error or running a fresh scan normally.

**Validates: Requirements 3.1, 3.2**

---

Property 3: Bug Condition – Device Provisioning Without Local Store Entry

_For any_ provisioning flow where `deviceId` is obtained from `connectAndReadDeviceId()` but the device is not yet in the local device store, the fixed `onboardingToken()` call SHALL succeed using the raw `deviceId` alone, without requiring a prior `deviceListProvider` entry.

**Validates: Requirements 2.3, 2.4**

---

Property 4: Preservation – Successful Provision Completion

_For any_ provisioning flow that completes successfully (token claimed, Wi-Fi sent if needed), the fixed code SHALL continue to call `deviceListProvider.notifier.load()` and navigate to `/connect`, unchanged from the original flow.

**Validates: Requirements 3.3, 3.4**

---

Property 5: Bug Condition – Back Navigation on Board Link Screen

_For any_ rendering of `BoardLinkScreen`, the fixed `AppBar` SHALL include a leading back arrow button that calls `context.pop()`, giving the user a visible return path.

**Validates: Requirements 2.5, 2.6**

---

Property 6: Preservation – Board Link Screen Functionality

_For any_ interaction on `BoardLinkScreen` that does NOT involve the back button (code entry, BLE scan push, form submit), the fixed code SHALL produce exactly the same behavior as the original.

**Validates: Requirements 3.5, 3.6**

---

Property 7: Bug Condition – Ambiguous STT Tokens Correctly Parsed

_For any_ STT result where a connector word (`'to'`, `'too'`, `'for'`) follows a file token inside `_parseSquare`, the fixed parser SHALL NOT consume that word as a rank digit. Instead it SHALL leave it for the skip loop to consume, and SHALL correctly read the destination square from subsequent tokens.

**Validates: Requirements 2.7, 2.9**

---

Property 8: Preservation – Special Commands and Illegal Moves

_For any_ STT input that does NOT trigger the token-ambiguity condition (special commands like `'undo'`, ordinary squares like `'d4'`, or illegal moves), the fixed parser SHALL return exactly the same `MoveParseResult` as the original parser.

**Validates: Requirements 3.7, 3.8**

---

Property 9: Bug Condition – Analysis Navigation Uses Push

_For any_ tap on the "Analyze" button in the Play screen, the fixed navigation SHALL use `context.push('/analysis?game_id=...')` so the Play screen remains on the stack, and the back button in `AnalysisScreen` SHALL successfully return to Play without a `GoError`.

**Validates: Requirements 2.10, 2.11**

---

Property 10: Preservation – Analysis Shell Route Unaffected

_For any_ navigation to the Analysis screen via the bottom navigation bar (shell route), the fixed code SHALL produce exactly the same behavior as before — the Analysis screen loads and back-navigates normally.

**Validates: Requirements 3.9, 3.10**

---

Property 11: Bug Condition – Draw Button Hidden vs Bot

_For any_ game state where `_gameMode` is `'human_vs_ai'` or `'phone_vs_board'`, the fixed `_GameControls` widget SHALL render the Draw button as disabled or hidden, preventing the user from offering a draw to a bot.

**Validates: Requirements 2.12, 2.13**

---

Property 12: Preservation – Draw Button in Human vs Human

_For any_ game state where `_gameMode` is `'human_vs_human'`, the fixed `_GameControls` widget SHALL render the Draw button in exactly the same enabled state as in the original code.

**Validates: Requirements 3.11, 3.12**

---

Property 13: Bug Condition – Resign Button Shows Confirmation Dialog

_For any_ tap on the Resign button in the Play screen, the fixed code SHALL show a confirmation dialog and, upon confirmation, call the resign API endpoint. The game state SHALL update to reflect resignation.

**Validates: Requirements 2.14, 2.15, 2.16**

---

Property 14: Preservation – Resign Dialog Cancellation and Post-Game State

_For any_ Resign button tap that is followed by dialog dismissal, or any state where the game is already over, the fixed code SHALL preserve the current game state without modification, identical to the original behavior.

**Validates: Requirements 3.13, 3.14**

---

Property 15: Bug Condition – Player Row Shows Authenticated Username

_For any_ rendering of `_PlayerRow` where `userProfileProvider` has resolved with a non-empty `displayName`, the fixed widget SHALL display that `displayName` rather than the hard-coded string `'PLAYER_ONE'`.

**Validates: Requirements 2.17, 2.18**

---

Property 16: Preservation – AI Row and Re-Navigation

_For any_ rendering of the AI player row, and for any re-navigation to the Play screen after the fix, the fixed code SHALL preserve the existing AI label display and show the correct player name without re-fetching, identical to the original behavior.

**Validates: Requirements 3.15, 3.16**

---

Property 17: Bug Condition – Opening/Lesson Context Passed to Play Screen

_For any_ navigation from an opening card or lesson card to the Play screen, the fixed code SHALL pass an `OpeningContext` (or `LessonContext`) as the route `extra`, causing the Play screen to load the associated position and display a guided hint panel.

**Validates: Requirements 2.19, 2.20, 2.21**

---

Property 18: Preservation – Regular New Game Unaffected

_For any_ navigation to the Play screen without an `extra` parameter (standard new game flow), the fixed Play screen SHALL start from the initial position with no lesson overlay, identical to the original behavior.

**Validates: Requirements 3.17, 3.18, 3.19**

---

Property 19: Bug Condition – Home Dashboard Displays Live User Data

_For any_ rendering of `HomeDashboard` where `userProfileProvider` and `userStatsProvider` have resolved, the fixed widget SHALL display the authenticated user's display name and at minimum their total games played and win/loss record.

**Validates: Requirements 2.24, 2.25, 2.26**

---

Property 20: Preservation – Dashboard Board and Loading State

_For any_ rendering of `HomeDashboard` where either provider is still loading, or where no active game exists, the fixed code SHALL continue to render the chess board section and the "Start a Game" button without crashing, identical to the original behavior.

**Validates: Requirements 3.21, 3.22**

---

## Fix Implementation

### BUG-1 — File: `lib/core/ble/robochess_ble.dart`

**Function:** `scan()`

**Change:** Replace `await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on` with a stream wait that filters for `on` with a 5-second timeout:

```dart
// Before
if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
  throw StateError('Bluetooth is disabled...');
}

// After
final state = await FlutterBluePlus.adapterState
    .firstWhere(
      (s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn,
    )
    .timeout(
      const Duration(seconds: 5),
      onTimeout: () => BluetoothAdapterState.off,
    );
if (state != BluetoothAdapterState.on) {
  throw StateError('Bluetooth is disabled. Turn on Bluetooth and try again.');
}
```

---

### BUG-2 — File: `lib/data/repositories/device_repository.dart` (verify) + `lib/data/datasources/device_remote.dart`

**Function:** `onboardingToken()`

**Change:** Verify that `onboardingToken()` makes a direct network call using the passed `deviceId` without any prior local-store lookup. If a local lookup exists, remove it. The raw `deviceId` from BLE is the authoritative identifier at this stage.

---

### BUG-3 — File: `lib/presentation/screens/board_link_screen.dart`

**Function:** `_BoardLinkScreenState.build()` → `AppBar`

**Change:** Add the `leading` parameter:

```dart
appBar: AppBar(
  backgroundColor: kBackground,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  leading: IconButton(
    icon: const Icon(Icons.arrow_back, color: kPrimary),
    onPressed: () => context.pop(),
  ),
  title: Text('Link Board', ...),
),
```

---

### BUG-4 — File: `lib/domain/voice/move_parser.dart`

**Function:** `_parseSquare()`

**Changes:**
1. Add a constant for ambiguous connector-rank words:
   ```dart
   const _connectorWords = {'to', 'too', 'for'};
   ```
2. In `_parseSquare`, when building a two-token file+rank pair, exclude connector words from the rank slot:
   ```dart
   if (_fileMap.containsKey(tok)) {
     final fileChar = _fileMap[tok]!;
     if (idx + 1 < tokens.length
         && _rankMap.containsKey(tokens[idx + 1])
         && !_connectorWords.contains(tokens[idx + 1])) {  // ← new guard
       final rankChar = _rankMap[tokens[idx + 1]]!;
       return ('$fileChar$rankChar', idx + 2);
     }
   }
   ```
3. Add `'be' → 'b'` to `_fileMap` (common STT mis-transcription for `'b'`):
   ```dart
   'be': 'b',
   ```

---

### BUG-5 — File: `lib/presentation/screens/play_screen.dart`

**Function:** `_PlayScreenState.build()` → `_GameControls(onAnalyze:)`

**Change:** Replace `context.go(...)` with `context.push(...)`:

```dart
// Before
onAnalyze: _linkedGameId != null
    ? () => context.go('/analysis?game_id=$_linkedGameId')
    : null,

// After
onAnalyze: _linkedGameId != null
    ? () => context.push('/analysis?game_id=$_linkedGameId')
    : null,
```

---

### BUG-6 — File: `lib/presentation/screens/play_screen.dart`

**Changes:**
1. Add `String _gameMode = 'human_vs_ai'` to `_PlayScreenState`.
2. In `_startGameFlow()`, after `result` is received: `setState(() { _gameMode = result.mode; ... })`.
3. Pass `gameMode: _gameMode` to `_GameControls`.
4. In `_GameControls`, add `final String gameMode` parameter. In `build()`, wrap the Draw `_ControlBtn` with a condition: `if (gameMode == 'human_vs_human') ...` or pass `onTap: null` and visually dim it otherwise.

---

### BUG-7 — Files: `play_screen.dart`, `game_provider.dart`, `game_repository.dart`, `game_remote.dart`

**Changes:**
1. `play_screen.dart`: Add `onResign` callback to `_GameControls`. Implement `_resignGame()` in `_PlayScreenState`:
   - Show `showDialog` with "Resign?" title and Confirm/Cancel actions.
   - On confirm: `ref.read(gameControllerProvider.notifier).resignGame(_linkedGameId!)`.
   - On failure: `setState(() => _syncError = 'Resign failed.')`.
2. `game_provider.dart`: Add `Future<void> resignGame(String gameId)` to `GameController`.
3. `game_repository.dart`: Add `Future<void> resignGame(String gameId)` calling `_remote.resignGame(gameId)`.
4. `game_remote.dart`: Add `resignGame(gameId)` → `POST /games/{gameId}/resign`. Catch 404/network errors and rethrow as `ApiException`.

---

### BUG-8 — File: `lib/presentation/screens/play_screen.dart`

**Function:** `_PlayerRow`

**Change:** Convert from `StatelessWidget` to `ConsumerWidget`. Read `ref.watch(userProfileProvider)`:

```dart
class _PlayerRow extends ConsumerWidget {
  final chess.Chess game;
  const _PlayerRow({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final displayName = profileAsync.valueOrNull?.displayName ?? 'Player';
    // replace 'PLAYER_ONE' with displayName.toUpperCase()
    ...
  }
}
```

---

### BUG-9/10 — Files: `domain/models/opening_context.dart` (new), `openings_screen.dart`, `lesson_track_screen.dart`, `learn_section.dart`, `play_screen.dart`

**Changes:**
1. Create `lib/domain/models/opening_context.dart`:
   ```dart
   class OpeningContext {
     final String name;
     final String pgn;
     const OpeningContext({required this.name, required this.pgn});
   }
   ```
2. `openings_screen.dart` – `_openLesson()`: Change `context.go('/play')` to `context.go('/play', extra: OpeningContext(name: opening.name, pgn: opening.notation))`.
3. `lesson_track_screen.dart` – `_LessonCard.build()`: Change `context.go('/play')` to `context.go('/play', extra: OpeningContext(name: lesson.title, pgn: lesson.objective))`.
4. `learn_section.dart` – `_CategoryCard`: Persist the category route to `FlutterSecureStorage(key: 'last_lesson_route')` when tapped. `_ContinueFAB`: Read the persisted value asynchronously; navigate to that route (fallback `'/learn/openings'`).
5. `play_screen.dart`:
   - In `_PlayScreenState`, add `OpeningContext? _openingContext`.
   - In `build()` (or `didChangeDependencies()`), read `GoRouterState.of(context).extra as OpeningContext?` and call `_loadOpeningContext(ctx)` if non-null.
   - `_loadOpeningContext()`: calls `_game.load_pgn(ctx.pgn)` and sets `_openingContext = ctx`.
   - Add a collapsible `_OpeningHintBanner` widget above the board when `_openingContext != null`, showing the opening name and the expected next move from the PGN line.

---

### BUG-11 — File: `lib/presentation/screens/home_dashboard.dart`

**Function:** `HomeDashboard.build()`

**Changes:**
1. Add `ref.watch(userProfileProvider)` and `ref.watch(userStatsProvider)`.
2. Render a greeting row above the board: `"Welcome back, [displayName]"` with loading skeleton when loading.
3. Render a stats row: games played, wins, losses — with loading skeleton or `'—'` placeholder when loading.
4. When `game != null`, show a "RESUME GAME" `FilledButton` alongside the existing "Start a Game" button.

---

## Testing Strategy

### Validation Approach

The testing strategy follows the bug condition methodology in two phases:
1. **Exploratory / Fix Checking**: Write tests that simulate each bug condition and assert the correct behavior after the fix. Run against unfixed code first to confirm the bug is observable, then against fixed code to confirm the property holds.
2. **Preservation Checking**: Write property-based or parameterized tests that sweep non-buggy inputs and assert that behavior is unchanged.

---

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate each bug BEFORE the fix. Confirm or refute the root cause analysis.

**Test Cases:**

1. **BLE Race (BUG-1)**: Mock `FlutterBluePlus.adapterState` to emit `unknown` then `on` after 100ms. Call `scan()` immediately. On unfixed code → `StateError` thrown. On fixed code → scan starts after 100ms delay, no error.

2. **Provision Without Local Store (BUG-2)**: Mock `deviceRepositoryProvider` with a `DeviceRepository` whose `onboardingToken()` throws if the device is not in a local list. On unfixed code → "Device not found" error. On fixed code → call succeeds with raw `deviceId`.

3. **Missing Back Button (BUG-3)**: Widget test: render `BoardLinkScreen` and verify `find.byIcon(Icons.arrow_back)`. On unfixed code → 0 matches. On fixed code → 1 match.

4. **STT Token Ambiguity (BUG-4)**: Unit test `parseMove('d to d4', board)`. On unfixed code → parses source as `d2`, connector consumed, destination fails. On fixed code → parses `d2 → d4` correctly (or source `d`, skip `to`, destination `d4`).

5. **GoError on Analysis Back (BUG-5)**: Integration test: pump `PlayScreen`, tap "Analyze", verify navigation stack depth is 2. Tap back → verify stack depth is 1. On unfixed code → `GoError` thrown. On fixed code → clean pop.

6. **Draw Button vs Bot (BUG-6)**: Widget test: render `_GameControls(gameMode: 'human_vs_ai', ...)`. On unfixed code → Draw button `enabled`. On fixed code → Draw button absent or `onTap: null`.

7. **Resign No-Op (BUG-7)**: Widget test: render `_GameControls` with mocked `onResign: null`. Tap Resign. On unfixed code → no dialog shown. On fixed code → dialog shown.

8. **Hard-Coded Player Name (BUG-8)**: Widget test: provide `userProfileProvider` override returning `UserProfile(displayName: 'Magnus', ...)`. Render `_PlayerRow`. On unfixed code → finds "PLAYER_ONE". On fixed code → finds "MAGNUS".

9. **Opening No Context (BUG-9)**: Widget test: tap "Practice This Opening" in `_OpeningCard`. On unfixed code → navigated route has no `extra`. On fixed code → `extra` is `OpeningContext`.

10. **Static Dashboard (BUG-11)**: Widget test: provide `userProfileProvider` override and `userStatsProvider` override. Render `HomeDashboard`. On unfixed code → "PLAYER_ONE" or no stats shown. On fixed code → display name and stats visible.

**Expected Counterexamples (unfixed code):**
- BUG-1: `StateError` on first scan
- BUG-3: Zero `Icons.arrow_back` icons in tree
- BUG-4: `MoveParseResult.failure(...)` for valid spoken moves with connector words
- BUG-5: `GoError` thrown during `context.pop()` in AnalysisScreen
- BUG-6: Draw `_ControlBtn` has `onTap != null` in bot game modes
- BUG-7: No dialog shown, no state change after Resign tap
- BUG-8: `Text('PLAYER_ONE')` found in widget tree

---

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := fixedFunction(input)
  ASSERT expectedBehavior(result)
END FOR
```

Key fix-checking assertions:

- `isBleFirstScanRace(X) = true` → `scan()` eventually calls `startScan` without error
- `isSTTAmbiguous(X) = true` → `parseMove(X)` returns a `MoveParseResult.success` with correct UCI
- `isGoErrorCrash(X) = true` → navigation stack has Play screen after pushing Analysis
- `isDrawButtonShownVsBot(X) = true` → Draw button is absent or disabled
- `isResignNoOp(X) = true` → confirmation dialog is displayed
- `isHardcodedPlayerName(X) = true` → display name from provider shown
- `isOpeningNoContext(X) = true` → `PlayScreen` receives `OpeningContext` in route extra
- `isStaticDashboard(X) = true` → user display name and stats rendered

---

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalFunction(input) = fixedFunction(input)
END FOR
```

**Property-based testing is recommended** for the move parser (BUG-4) because the input space is large. Generate random combinations of valid square tokens, special commands, and promotions; assert `parseMove(unfixed)` == `parseMove(fixed)` for all non-ambiguous inputs.

**Test Cases:**

1. **BLE — Subsequent Scans**: Mock adapter as immediately `on`. Call `scan()` twice. Both calls return scan results without error.
2. **BLE — Disabled Bluetooth**: Mock adapter never reaches `on`. Call `scan()`. Confirm `StateError("Bluetooth is disabled")` thrown.
3. **Move Parser — Special Commands**: `parseMove('undo')`, `parseMove('resign')` → same `MoveParseResult.command` as before.
4. **Move Parser — Clean Squares**: Property test with generated tokens from `['a','b','c',...,'h']` × `['1'..'8']` as single tokens. Assert no regression.
5. **Move Parser — Illegal Moves**: `parseMove('e2 e5', board_with_e5_occupied)` → same `MoveParseResult.failure` as before.
6. **Analysis Shell Route**: Navigate to Analysis from bottom nav. Assert screen loads and back-navigation works normally.
7. **Draw Button — HvH Mode**: `_GameControls(gameMode: 'human_vs_human')` → Draw button present and enabled.
8. **Dashboard — No Active Game**: `gameControllerProvider` returns null. Dashboard shows "Start a Game", no "Resume Game" button.
9. **Dashboard — Loading State**: `userProfileProvider` in loading state. Dashboard renders without crash, shows skeleton.

---

### Unit Tests

- `move_parser_test.dart`:
  - `'d to d4'` → `d2d4` (or assert ambiguous-connector skip)
  - `'g 7'` → `g7` parsed as destination
  - `'be 4'` → `b4`
  - `'undo'` → `UNDO` command
  - `'e2 to e4'` → `e2e4` with board validation

- `ble_scan_test.dart`:
  - Adapter `unknown → on` after delay → scan starts without error
  - Adapter stays `off` → `StateError` thrown with correct message

- `board_link_screen_test.dart`:
  - `Icons.arrow_back` present in widget tree
  - Tapping back arrow calls `context.pop()`

- `player_row_test.dart`:
  - With `userProfileProvider` override → display name shown
  - With `userProfileProvider` loading → fallback `'Player'` shown

- `game_controls_test.dart`:
  - `gameMode = 'human_vs_ai'` → Draw button absent or disabled
  - `gameMode = 'human_vs_human'` → Draw button enabled
  - Resign tap → dialog shown

- `home_dashboard_test.dart`:
  - Profile and stats providers resolved → name and stats rendered
  - Providers loading → no crash, skeleton shown

---

### Property-Based Tests

- **Move Parser Preservation**: For randomly generated move strings that do not contain connector words in ambiguous positions, assert `parseMove(input)` returns identical result before and after the fix.
- **Game Mode Draw Button**: For all values of `gameMode`, assert Draw button enabled status is correct (`human_vs_human` → enabled, others → disabled/hidden).
- **Dashboard Provider States**: For all combinations of `(profile: loading|data|error) × (stats: loading|data|error)`, assert `HomeDashboard` renders without uncaught exceptions.

---

### Integration Tests

- End-to-end: Open Learn → tap Opening card → arrive at Play with position loaded and hint banner visible.
- End-to-end: Open Play → tap Analyze → arrive at Analysis → tap back → arrive at Play (no GoError).
- End-to-end: Start BLE scan on first tap → scan results appear (mocked BLE environment).
- End-to-end: Open Home → user stats and name visible after login.


---

### BUG-12 – Hardcoded Server URL (app_config.dart → server_config_store.dart + session_provider.dart + login_screen.dart)

`AppConfig.apiBaseUrl` and `AppConfig.wsBaseUrl` are resolved by `String.fromEnvironment` at compile time. Without a USB-tethering connection to `172.20.10.3`, every API call (including login) throws a `SocketException` or `TimeoutException` and the app is completely non-functional. The fix introduces a `ServerConfigStore` that persists a runtime-configurable base URL in `FlutterSecureStorage`, exposes it through a `StateNotifierProvider`, wires `apiClientProvider` and `gameSocketProvider` to read from that provider, and adds a "Configure server" affordance on the login screen.

**Formal Specification:**

```
FUNCTION isHardcodedServerUrl(X)
  INPUT: X = { runtimeUrlSaved: bool, networkReachable: bool }
  OUTPUT: boolean

  RETURN NOT X.runtimeUrlSaved AND NOT X.networkReachable
END FUNCTION
```

**Examples:**
- App launched on home WiFi, no USB cable, no persisted URL → every API call fails with `SocketException` — **bug**
- App launched after user saved `http://192.168.1.42:8000` → `apiClientProvider` uses saved URL — correct
- App built with `--dart-define=API_BASE_URL=http://10.0.0.5:8000`, no runtime override → uses compile-time value — **preserved**
- `TokenStore` read/write → unaffected, uses same keys as before — **preserved**

---

## BUG-12 — New File: `lib/core/config/server_config_store.dart`

Uses the same `flutter_secure_storage` package already in the project (used by `TokenStore`). The storage key `'server_base_url'` is intentionally distinct from all `TokenStore` keys (`access_token`, `refresh_token`, `user_id`, `selected_device_id`).

```dart
class ServerConfigStore {
  static const _baseUrlKey = 'server_base_url';

  final FlutterSecureStorage _storage;

  ServerConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> loadBaseUrl() => _storage.read(key: _baseUrlKey);

  Future<void> saveBaseUrl(String url) =>
      _storage.write(key: _baseUrlKey, value: url);

  Future<void> clear() => _storage.delete(key: _baseUrlKey);
}
```

**Key isolation:** `ServerConfigStore` reads and writes only `'server_base_url'`. It never touches `'access_token'`, `'refresh_token'`, `'user_id'`, or `'selected_device_id'`, satisfying Requirement 3.25.

---

## BUG-12 — New Riverpod Provider: `ServerConfigNotifier`

Located in a new `lib/core/config/server_config_provider.dart` file (or appended to `session_provider.dart` — new file preferred to keep surface area minimal).

```
CLASS ServerConfigNotifier EXTENDS StateNotifier<String>
  CONSTRUCTOR(serverConfigStore, compiletimeFallback)
    super(compiletimeFallback)
    _load()

  FUNCTION _load()
    url ← serverConfigStore.loadBaseUrl()
    IF url != null THEN state ← url

  FUNCTION update(url: String)
    VALIDATE url IS non-empty AND starts with 'http://' OR 'https://'
    IF invalid THEN THROW ArgumentError('Enter a valid HTTP or HTTPS URL')
    AWAIT serverConfigStore.saveBaseUrl(url)
    state ← url
    // Riverpod automatically rebuilds apiClientProvider watchers

  FUNCTION reset()
    AWAIT serverConfigStore.clear()
    state ← compiletimeFallback
END CLASS
```

The provider declaration:

```dart
final serverConfigStoreProvider = Provider<ServerConfigStore>(
  (ref) => ServerConfigStore(),
);

final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, String>((ref) {
  return ServerConfigNotifier(
    ref.read(serverConfigStoreProvider),
    AppConfig.apiBaseUrl,   // compile-time fallback
  );
});
```

The initial state is always `AppConfig.apiBaseUrl`. `_load()` runs asynchronously and updates state once the persisted value (if any) is read from secure storage. This means on first build `apiClientProvider` may briefly use the compile-time value before `_load()` completes; the `ApiClient` is reconstructed when state changes, which happens before the user has a chance to trigger a network call from the login screen in practice.

---

## BUG-12 — Updated `apiClientProvider` (session_provider.dart)

**Before:**
```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokenStore: ref.read(tokenStoreProvider),
      timeout: Duration(seconds: AppConfig.apiTimeoutSeconds));
});
```

**After:**
```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(serverConfigProvider);   // ← watches runtime URL
  return ApiClient(
      baseUrl: baseUrl,
      tokenStore: ref.read(tokenStoreProvider),
      timeout: Duration(seconds: AppConfig.apiTimeoutSeconds));
});
```

Switching from `ref.read` to `ref.watch` on `serverConfigProvider` means that whenever the user saves a new URL, `serverConfigProvider` state changes, `apiClientProvider` is automatically invalidated and reconstructed with the new `baseUrl`. All downstream providers that `ref.watch(apiClientProvider)` — including `authRepositoryProvider`, `deviceRepositoryProvider`, `gameRepositoryProvider` — are also rebuilt in the same reactive cycle.

---

## BUG-12 — Updated `gameSocketProvider` (session_provider.dart)

The WebSocket URL is derived from the HTTP base URL to keep a single source of truth. The derivation rule: replace the scheme (`http` → `ws`, `https` → `wss`) and append `/ws`.

**Before:**
```dart
final gameSocketProvider = Provider<GameSocketClient>((ref) {
  return GameSocketClient(wsBaseUrl: AppConfig.wsBaseUrl);
});
```

**After:**
```dart
final gameSocketProvider = Provider<GameSocketClient>((ref) {
  final httpBase = ref.watch(serverConfigProvider);
  final wsBase = httpBase
      .replaceFirst(RegExp(r'^https://'), 'wss://')
      .replaceFirst(RegExp(r'^http://'), 'ws://')
      + '/ws';
  return GameSocketClient(wsBaseUrl: wsBase);
});
```

This approach avoids storing a second URL and keeps the WS endpoint consistent with whatever HTTP base the user configures. If a project in the future needs an independent WS URL, `ServerConfigStore` can be extended to persist `'server_ws_url'` separately without breaking the existing key.

---

## BUG-12 — Login Screen: "Configure server" Affordance (login_screen.dart)

A compact `TextButton` is added below the existing form card, showing the currently active base URL. Tapping it opens an `AlertDialog` with a pre-filled `TextFormField`. Saving validates and calls `ref.read(serverConfigProvider.notifier).update(url)`.

```
WIDGET _ServerConfigButton
  READS: ref.watch(serverConfigProvider)  // to display current URL
  TAPS:  _showConfigDialog(context, ref, currentUrl)

DIALOG _showConfigDialog
  TextFormField pre-filled with currentUrl
  VALIDATOR:
    IF url.isEmpty OR NOT (url.startsWith('http://') OR url.startsWith('https://'))
      RETURN 'Enter a valid HTTP or HTTPS URL'
  ON SAVE:
    ref.read(serverConfigProvider.notifier).update(trimmedUrl)
    context.pop()
  ON CANCEL:
    context.pop() (no change)
```

The button is placed after the existing `TextButton.icon` for "PLAY LOCALLY WITHOUT INTERNET" so it does not disrupt the primary login flow. Display text: `"⚙ Server: $currentUrl"` (truncated to 40 chars if long) in `kOnSurfaceVariant` color with font size 11 to keep it visually subordinate.

---

## Correctness Properties (BUG-12)

Property 21: Bug Condition – Runtime URL Used When Persisted

_For any_ app launch where a URL has previously been saved to `FlutterSecureStorage` under key `'server_base_url'`, the fixed `apiClientProvider` SHALL construct an `ApiClient` whose `baseUrl` equals the persisted URL, not `AppConfig.apiBaseUrl` (`http://172.20.10.3:8000`).

**Validates: Requirements 2.27**

---

Property 22: Preservation – Compile-Time Fallback When No Runtime URL Saved

_For any_ app launch where no runtime URL has been persisted (key `'server_base_url'` is absent from `FlutterSecureStorage`), the fixed `apiClientProvider` SHALL construct an `ApiClient` whose `baseUrl` equals `AppConfig.apiBaseUrl`, preserving the existing `--dart-define` developer workflow with no behaviour change.

**Validates: Requirements 2.28, 3.23**

---

Property 23: Bug Condition – Provider Reconstruction After URL Update

_For any_ call to `serverConfigProvider.notifier.update(newUrl)` where `newUrl` is a valid HTTP/HTTPS URL, the fixed code SHALL update `serverConfigProvider` state to `newUrl`, causing `apiClientProvider` to be reconstructed so that subsequent API calls use `newUrl` as `baseUrl`, without requiring an app restart.

**Validates: Requirements 2.29, 3.24**

---

Property 24: Preservation – TokenStore Key Isolation

_For any_ read or write to `TokenStore` (keys `access_token`, `refresh_token`, `user_id`, `selected_device_id`), the fixed code SHALL produce exactly the same result as before. `ServerConfigStore` SHALL use only key `'server_base_url'`, which has no overlap with any `TokenStore` key.

**Validates: Requirements 3.25**

---

## Fix Implementation (BUG-12)

### Changes Required

**File 1 (new): `lib/core/config/server_config_store.dart`**
- Implement `ServerConfigStore` with `loadBaseUrl()`, `saveBaseUrl(String)`, `clear()`.
- Use `FlutterSecureStorage` with key `'server_base_url'`.

**File 2 (new): `lib/core/config/server_config_provider.dart`**
- Implement `ServerConfigNotifier extends StateNotifier<String>`.
- Constructor accepts `ServerConfigStore` and compile-time fallback string; calls `_load()`.
- `_load()`: reads persisted URL, updates state if non-null.
- `update(String url)`: validates scheme (`http://` or `https://`), persists, updates state. Throws `ArgumentError` with user-readable message on invalid input.
- `reset()`: clears persisted value, resets state to compile-time fallback.
- Declare `serverConfigStoreProvider` (plain `Provider`) and `serverConfigProvider` (`StateNotifierProvider`).

**File 3 (modify): `lib/presentation/providers/session_provider.dart`**
- Add import for `server_config_provider.dart`.
- Change `apiClientProvider`: replace `AppConfig.apiBaseUrl` with `ref.watch(serverConfigProvider)`.
- Change `gameSocketProvider`: derive WS URL from `ref.watch(serverConfigProvider)` using scheme replacement + `/ws` suffix.

**File 4 (modify): `lib/presentation/screens/login_screen.dart`**
- Add import for `server_config_provider.dart`.
- Add `_ServerConfigButton` `ConsumerWidget` (or inline `Consumer`) below the "PLAY LOCALLY" button.
- Implement `_showServerConfigDialog(BuildContext, WidgetRef, String currentUrl)`: `AlertDialog` with `TextFormField`, validation, save/cancel actions.

### Specific Changes

1. **`server_config_store.dart` (new)**: Single-responsibility class for `FlutterSecureStorage` r/w of `'server_base_url'`. Mirrors the structure of `TokenStore` for consistency with the existing codebase pattern.

2. **`server_config_provider.dart` (new)**: `ServerConfigNotifier` with async init pattern (same pattern as `SessionController._load()`). Initial synchronous state is the compile-time fallback so no `null` handling is needed downstream.

3. **`session_provider.dart` — `apiClientProvider`**: Change `ref.read` to `ref.watch` on `serverConfigProvider`. This is the only change needed to make the client reactive to URL updates.

4. **`session_provider.dart` — `gameSocketProvider`**: Same reactive pattern. WS URL derived by string transformation to avoid a second storage key and keep both URLs in sync automatically.

5. **`login_screen.dart` — Configure server button**: Minimal UI addition that does not modify existing form logic. The dialog uses the same `InputDecoration` helper (`_inputDecoration`) already defined in the file for visual consistency.

---

## Testing Strategy (BUG-12)

### Exploratory Bug Condition Checking

**Goal**: Demonstrate that without the fix, `apiClientProvider` always uses the hardcoded compile-time URL regardless of what is stored in `FlutterSecureStorage`.

**Test Cases:**

1. **Persisted URL Ignored (unfixed code)**: Seed `FlutterSecureStorage` with `server_base_url = 'http://192.168.1.1:8000'`. Construct `apiClientProvider`. Assert `client.baseUrl == 'http://172.20.10.3:8000'` — confirms the bug (persisted URL is ignored).

2. **Configure Dialog Missing (unfixed code)**: Render `LoginScreen`. Assert `find.text('Configure server')` or `find.byIcon(Icons.settings)` returns zero widgets.

**Expected Counterexamples:**
- `apiClientProvider.baseUrl` always equals the compile-time constant regardless of `FlutterSecureStorage` content.
- No "Configure server" affordance in the login UI.

### Fix Checking

**Goal**: Verify each correctness property holds after the fix.

**Test Cases:**

1. **Property 21 – Persisted URL Used**: Seed `FlutterSecureStorage` with `server_base_url = 'http://10.0.0.50:8000'`. Boot `serverConfigProvider` and await `_load()`. Assert `serverConfigProvider.state == 'http://10.0.0.50:8000'`. Assert `apiClientProvider.baseUrl == 'http://10.0.0.50:8000'`.

2. **Property 22 – Fallback to Compile-Time**: Empty `FlutterSecureStorage`. Boot `serverConfigProvider`. Assert `serverConfigProvider.state == AppConfig.apiBaseUrl`.

3. **Property 23 – URL Update Reconstructs Client**: Call `serverConfigProvider.notifier.update('http://192.168.0.5:8000')`. Assert `apiClientProvider.baseUrl == 'http://192.168.0.5:8000'` without app restart.

4. **Property 23 – WS URL Derived Correctly**: After `update('http://192.168.0.5:8000')`, assert `gameSocketProvider.wsBaseUrl == 'ws://192.168.0.5:8000/ws'`.

5. **Property 23 – HTTPS Scheme**: After `update('https://api.example.com')`, assert `gameSocketProvider.wsBaseUrl == 'wss://api.example.com/ws'`.

6. **Property 24 – Key Isolation**: After `serverConfigProvider.notifier.update(...)`, assert `FlutterSecureStorage` keys `access_token`, `refresh_token`, `user_id`, `selected_device_id` are unmodified.

7. **Validation – Empty URL Rejected**: Call `serverConfigProvider.notifier.update('')`. Assert `ArgumentError` thrown with user-readable message.

8. **Validation – Non-HTTP URL Rejected**: Call `serverConfigProvider.notifier.update('ftp://example.com')`. Assert `ArgumentError` thrown.

9. **Configure Dialog – Valid Save**: Render `LoginScreen` with `serverConfigProvider` override. Tap "Configure server". Enter `'http://10.0.0.1:8000'` in field. Tap Save. Assert `serverConfigProvider.state == 'http://10.0.0.1:8000'`.

10. **Configure Dialog – Invalid URL Shows Error**: Enter `'not-a-url'`. Tap Save. Assert dialog remains open and error text is shown. Assert `serverConfigProvider.state` unchanged.

### Preservation Checking

**Pseudocode:**
```
FOR ALL X WHERE NOT isHardcodedServerUrl(X) DO
  ASSERT apiClientProvider(original)(X) = apiClientProvider(fixed)(X)
END FOR
```

**Test Cases:**

1. **`--dart-define` Workflow**: When `FlutterSecureStorage` is empty and `AppConfig.apiBaseUrl` is `'http://custom.compile.time:8000'` (simulated via provider override), `apiClientProvider.baseUrl` equals that value — same as before the fix.

2. **TokenStore Unchanged**: Read and write `TokenStore` before and after calling `serverConfigProvider.notifier.update(...)`. Assert all token keys (`access_token`, `refresh_token`, `user_id`, `selected_device_id`) have identical values.

3. **Login Flow Unaffected**: Full widget test of the login flow (enter email + password, tap Sign In, mock successful auth). Assert `SessionController.login()` is called and the user is navigated to `/home`. Assert no regression from the new button in the UI.

4. **All Auth Providers Rebuilt**: After URL update, verify `authRepositoryProvider`, `deviceRepositoryProvider`, and `gameRepositoryProvider` all hold instances whose underlying `ApiClient` uses the new URL (they depend on `apiClientProvider` which is now rebuilt).

### Unit Tests

- `server_config_store_test.dart`:
  - `saveBaseUrl` then `loadBaseUrl` returns the saved value.
  - `clear` then `loadBaseUrl` returns null.
  - Key used is exactly `'server_base_url'` (no other keys written).

- `server_config_provider_test.dart`:
  - With persisted URL → notifier state equals persisted URL after init.
  - Without persisted URL → notifier state equals `AppConfig.apiBaseUrl` fallback.
  - `update('http://valid:8000')` → state updated, value persisted.
  - `update('')` → `ArgumentError` thrown, state unchanged.
  - `update('ftp://bad')` → `ArgumentError` thrown.
  - `reset()` → state reverts to compile-time fallback, stored value cleared.

- `session_provider_test.dart` (additions):
  - `apiClientProvider` with `serverConfigProvider` override `'http://test:8000'` → `client.baseUrl == 'http://test:8000'`.
  - `gameSocketProvider` with `serverConfigProvider` override `'http://test:8000'` → `wsBaseUrl == 'ws://test:8000/ws'`.
  - `gameSocketProvider` with `https` base → `wsBaseUrl` starts with `'wss://'`.

- `login_screen_test.dart` (additions):
  - "Configure server" button/text present in widget tree.
  - Tapping it opens `AlertDialog` with a `TextFormField`.
  - Entering valid URL and saving closes dialog, updates provider state.
  - Entering invalid URL and saving keeps dialog open, shows error.

### Property-Based Tests

- **URL Scheme Derivation**: For any URL starting with `'http://'`, assert derived WS URL starts with `'ws://'` and ends with `'/ws'`. For any URL starting with `'https://'`, assert derived WS URL starts with `'wss://'`.
- **Key Non-Collision**: For any sequence of `saveBaseUrl` and `TokenStore.saveSession` calls, assert that `TokenStore.loadSession()` returns the originally saved session unchanged.
- **Validation Boundary**: For randomly generated strings, assert `update(s)` throws `ArgumentError` if and only if `s` does not start with `'http://'` or `'https://'` or is empty.

### Integration Tests

- End-to-end: Cold start with persisted URL `'http://192.168.1.99:8000'` → login attempt hits `192.168.1.99:8000` (observable via mock HTTP client).
- End-to-end: Open login screen → tap Configure server → change URL → close dialog → attempt login → new URL used in HTTP request.
- End-to-end: Change URL while authenticated session is active → new API calls use the new URL, existing `TokenStore` session tokens unchanged.
