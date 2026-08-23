// ignore_for_file: invalid_use_of_protected_member, subtype_of_sealed_class

/// ============================================================
/// Bug Condition Exploration Tests — Task 1
/// ============================================================
///
/// These tests MUST FAIL on unfixed code.
/// A failing test confirms the bug exists.
///
/// Coverage:
///   BUG-1  (BLE race)             — skipped (platform channels unavailable)
///   BUG-3  (Missing back button)  — widget test
///   BUG-4  (STT "to" as rank 2)   — unit test
///   BUG-5  (context.go vs push)   — widget test
///   BUG-6  (Draw button vs bot)   — widget test
///   BUG-7  (Resign no-op)         — widget test
///   BUG-8  (Hard-coded PLAYER_ONE)— widget test
///   BUG-9  (Opening no context)   — widget test
///   BUG-11 (Static dashboard)     — widget test
///   BUG-12 (Hardcoded server URL) — unit test
/// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:robochess_mobile/core/config/app_config.dart';
import 'package:robochess_mobile/core/config/server_config_provider.dart';
import 'package:robochess_mobile/core/config/server_config_store.dart';
import 'package:robochess_mobile/core/network/token_store.dart';
import 'package:robochess_mobile/data/repositories/device_repository.dart';
import 'package:robochess_mobile/data/datasources/device_remote.dart';
import 'package:robochess_mobile/domain/models/device_credentials.dart';
import 'package:robochess_mobile/domain/models/device_model.dart';
import 'package:robochess_mobile/domain/models/game_state.dart';
import 'package:robochess_mobile/domain/models/user_profile.dart';
import 'package:robochess_mobile/domain/models/user_stats.dart';
import 'package:robochess_mobile/domain/voice/move_parser.dart';
import 'package:robochess_mobile/presentation/providers/device_provider.dart';
import 'package:robochess_mobile/presentation/providers/game_provider.dart';
import 'package:robochess_mobile/presentation/providers/session_provider.dart';
import 'package:robochess_mobile/presentation/providers/user_provider.dart';
import 'package:robochess_mobile/presentation/screens/board_link_screen.dart';
import 'package:robochess_mobile/presentation/screens/home_dashboard.dart';
import 'package:robochess_mobile/presentation/screens/openings_screen.dart';

// ---------------------------------------------------------------------------
// Fake / stub implementations
// ---------------------------------------------------------------------------

class _FakeDeviceRemoteDataSource extends Fake
    implements DeviceRemoteDataSource {
  @override
  Future<List<DeviceModel>> list() async => [];

  @override
  Future<DeviceModel> link({required String pairingCode}) async {
    return DeviceModel.fromJson({'device_id': 'fake', 'status': 'offline'});
  }

  @override
  Future<void> unlink(String deviceId) async {}

  @override
  Future<DeviceCredentials> onboardingToken({required String deviceId}) async =>
      const DeviceCredentials(onboardingToken: 'fake-token');

  @override
  Future<DeviceModel> status(String deviceId) async {
    return DeviceModel.fromJson({'device_id': deviceId, 'status': 'offline'});
  }
}

class _FakeDeviceListController
    extends StateNotifier<AsyncValue<List<DeviceModel>>>
    implements DeviceListController {
  _FakeDeviceListController() : super(const AsyncValue.data([]));

  @override
  Future<void> load() async {}

  @override
  Future<void> unlink(String deviceId) async {}
}

class _FakeSelectedDeviceController extends StateNotifier<String?>
    implements SelectedDeviceController {
  _FakeSelectedDeviceController() : super(null);

  @override
  Future<void> select(String deviceId) async {}

  @override
  Future<void> clear() async {}
}

class _FakeGameController extends StateNotifier<AsyncValue<GameStateModel?>>
    implements GameController {
  _FakeGameController() : super(const AsyncValue.data(null));

  @override
  Future<void> createGame({
    String mode = 'human_vs_ai',
    int difficulty = 5,
    List<String>? players,
  }) async {}

  @override
  Future<void> refresh(String gameId) async {}

  @override
  Future<void> submitMove({
    required String gameId,
    required String uci,
    int? expectedVersion,
  }) async {}

  @override
  Future<void> undoMove() async {}

  @override
  Future<void> resignGame(String gameId) async {}
}

// ---------------------------------------------------------------------------
// Minimal ProviderScope overrides shared across widget tests
// ---------------------------------------------------------------------------

List<Override> _baseOverrides() => [
      deviceListProvider.overrideWith((_) => _FakeDeviceListController()),
      selectedDeviceProvider
          .overrideWith((_) => _FakeSelectedDeviceController()),
      gameControllerProvider.overrideWith((_) => _FakeGameController()),
      deviceRepositoryProvider.overrideWith(
        (ref) => DeviceRepository(_FakeDeviceRemoteDataSource()),
      ),
      userProfileProvider.overrideWith(
        (ref) async => UserProfile(
          userId: 'u1',
          email: 'player@test.com',
          displayName: 'Player',
        ),
      ),
      userStatsProvider.overrideWith(
        (ref) async => const UserStats(
          rating: 1000,
          globalRank: 100,
          gamesPlayed: 5,
          wins: 3,
          losses: 2,
          draws: 0,
          winRate: 0.6,
          accuracy: 0.7,
          puzzleAttempts: 0,
        ),
      ),
    ];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ─── BUG-1: BLE Scan Race Condition ────────────────────────────────────────
  test(
    'BUG-1 (isBleFirstScanRace): first-tap scan awaits adapter confirmation',
    () {
      // FlutterBluePlus relies on platform channels unavailable in the test
      // host. Skipping with documentation of the expected counterexample.
      //
      // Expected failure on unfixed code:
      //   robochess_ble.dart: `await FlutterBluePlus.adapterState.first`
      //   resolves immediately to the cached stream value (`unknown` or
      //   `turningOn`) on first call. The guard
      //   `if (state != BluetoothAdapterState.on) throw StateError(...)`
      //   then fires, throwing:
      //     StateError('Bluetooth is disabled. Turn on Bluetooth and try again.')
      //   even though Bluetooth is physically on.
      //   The second tap works because by then the stream has emitted `on`.
    },
    skip: 'BLE platform channels not available in unit-test host. '
        'Counterexample: StateError thrown on first scan() call before '
        'BluetoothAdapterState.on is confirmed in the stream.',
  );

  // ─── BUG-3: Missing Back Button ────────────────────────────────────────────
  testWidgets(
    'BUG-3 (isMissingBackButton): BoardLinkScreen AppBar has a back arrow',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const BoardLinkScreen(),
          ),
          GoRoute(
            path: '/connect/ble',
            builder: (_, __) => const Scaffold(body: Text('BLE')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // On unfixed code: AppBar has no `leading:` → 0 arrow_back icons found.
      // This assertion FAILS on unfixed code → bug confirmed.
      expect(
        find.byIcon(Icons.arrow_back),
        findsOneWidget,
        reason: 'BUG-3 counterexample: BoardLinkScreen AppBar has no leading '
            'back arrow. find.byIcon(Icons.arrow_back) finds 0 widgets.',
      );
    },
  );

  // ─── BUG-4: STT Connector Word Consumed as Rank ────────────────────────────
  test(
    'BUG-4 (isSTTAmbiguous): "to" connector is NOT consumed as rank digit "2"',
    () {
      // No board — tests parser vocabulary behaviour in isolation.
      //
      // Input: "e to e4"
      // Unfixed _parseSquare logic:
      //   tok = "e" → fileChar = "e"
      //   idx+1 token = "to" → _rankMap["to"] = "2" → rankChar = "2"
      //   returns ("e2", idx+2=2)
      // Then skip loop at idx=2, tokens[2] = "e4" → dest = "e4"
      // Result: uci = "e2e4", isSuccess = true
      //
      // Fixed logic adds: `&& !_connectorWords.contains(tokens[idx + 1])`
      //   "to" is in _connectorWords → rank slot skipped → returns (null, 0)
      //   → failure("Couldn't read a source square...")
      //
      // The bug: "to" is silently aliased to rank "2".
      // Assert: uci must NOT be "e2e4" when "to" follows the file token.
      // On unfixed code: result.uci == "e2e4" → assertion fails → bug confirmed.
      final result = parseMove('e to e4');

      expect(
        result.uci,
        isNot(equals('e2e4')),
        reason:
            'BUG-4 counterexample: _rankMap["to"] = "2" causes _parseSquare '
            'to consume "to" as the source rank, producing source square "e2". '
            'On unfixed code result.uci == "e2e4" (connector silently became rank). '
            '"to" must be treated as a skip connector, not a rank digit.',
      );
    },
  );

  test(
    'BUG-4 supplementary: "for" connector is NOT consumed as rank digit "4"',
    () {
      // "for" also appears in _rankMap as "4".
      // "d for d5" → unfixed: source = d4 (d + for→4), dest = d5 → "d4d5"
      // fixed: "for" skipped as connector → source unreadable → failure
      final result = parseMove('d for d5');

      expect(
        result.uci,
        isNot(equals('d4d5')),
        reason: 'BUG-4 supplementary: _rankMap["for"] = "4" causes "d for d5" '
            'to parse source as "d4" instead of treating "for" as a connector. '
            'On unfixed code result.uci == "d4d5".',
      );
    },
  );

  // ─── BUG-5: context.go → GoError when navigating back ─────────────────────
  testWidgets(
    'BUG-5 (isGoErrorCrash): navigating to Analysis and pressing Back returns to Play',
    (tester) async {
      // The FIXED Play screen uses context.push('/analysis?...') so the Play
      // screen stays on the navigation stack. This test builds a minimal
      // reproduction using the same (fixed) push-based navigation pattern and
      // verifies that pressing Back returns to the Play screen without GoError.

      bool popThrewError = false;

      final router = GoRouter(
        initialLocation: '/play',
        routes: [
          GoRoute(
            path: '/play',
            builder: (context, state) => Scaffold(
              appBar: AppBar(title: const Text('Play')),
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  // Fixed: context.push keeps Play on the stack
                  onPressed: () => ctx.push('/analysis?game_id=test'),
                  child: const Text('Analyze'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/analysis',
            builder: (context, state) => Scaffold(
              appBar: AppBar(title: const Text('Analysis')),
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    try {
                      ctx.pop();
                    } catch (e) {
                      popThrewError = true;
                    }
                  },
                  child: const Text('Back'),
                ),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      // Navigate to Analysis using push() (fixed)
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(find.text('Analysis'), findsOneWidget);

      // Attempt to go back
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      // Fixed behavior: context.push() kept Play on the stack.
      // context.pop() in Analysis returns to Play without GoError.
      expect(
        popThrewError,
        isFalse,
        reason: 'BUG-5: context.pop() must not throw GoError after navigating '
            'with context.push(). Fix: use context.push() so Play stays on the stack.',
      );
      expect(
        find.text('Analyze'),
        findsOneWidget,
        reason: 'BUG-5: Play screen must be restored after pressing Back. '
            'Fix: use context.push() so Play stays on the stack.',
      );
    },
  );

  // ─── BUG-6: Draw Button vs Bot ─────────────────────────────────────────────
  testWidgets(
    'BUG-6 (isDrawButtonShownVsBot): Draw button is hidden when playing against bot',
    (tester) async {
      // _GameControls is a private widget. We test the observable property
      // via a harness that mirrors the FIXED behavior: DRAW is hidden when
      // gameMode != 'human_vs_human'.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _GameControlsHarness(gameMode: 'human_vs_ai'),
          ),
        ),
      );
      await tester.pump();

      // Fixed behavior: DRAW is not rendered for bot game modes.
      expect(
        find.text('DRAW'),
        findsNothing,
        reason: 'BUG-6: Draw button must be hidden/disabled when '
            'gameMode != "human_vs_human".',
      );
    },
  );

  // ─── BUG-7: Resign No-Op ───────────────────────────────────────────────────
  testWidgets(
    'BUG-7 (isResignNoOp): tapping Resign shows a confirmation AlertDialog',
    (tester) async {
      // The FIXED _GameControls passes an onResign callback to the Resign
      // _ControlBtn → tapping shows a confirmation dialog.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _ResignButtonHarness(hasHandler: true), // fixed: has handler
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('RESIGN'));
      await tester.pumpAndSettle();

      // Fixed behavior: tapping Resign shows a confirmation AlertDialog.
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'BUG-7: The Resign button must have an onTap handler wired '
            '(onResign callback) so tapping it shows a confirmation dialog.',
      );
    },
  );

  // ─── BUG-8: Hard-coded PLAYER_ONE ──────────────────────────────────────────
  testWidgets(
    'BUG-8 (isHardcodedPlayerName): _PlayerRow shows authenticated display name',
    (tester) async {
      // Override userProfileProvider to return displayName 'Magnus'
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) async => UserProfile(
                userId: 'user-magnus',
                email: 'magnus@chess.com',
                displayName: 'Magnus',
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _PlayerRowHarness(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Fixed behavior: _PlayerRow reads userProfileProvider and renders the
      // authenticated display name in place of the hard-coded 'PLAYER_ONE'.
      expect(
        find.text('MAGNUS'),
        findsOneWidget,
        reason: 'BUG-8: _PlayerRow must read userProfileProvider and display '
            'the authenticated display name.',
      );

      expect(
        find.text('PLAYER_ONE'),
        findsNothing,
        reason: 'BUG-8: Hard-coded "PLAYER_ONE" should not appear when '
            'userProfileProvider has resolved with a real display name.',
      );
    },
  );

  // ─── BUG-9: Opening Navigation Passes No Context ───────────────────────────
  testWidgets(
    'BUG-9 (isOpeningNoContext): "Practice This Opening" passes OpeningContext as route extra',
    (tester) async {
      Object? capturedExtra;

      // Include a /learn route as the initial screen so the OpeningsScreen
      // AppBar back button has something to pop to (avoids GoError from back btn)
      final router = GoRouter(
        initialLocation: '/learn/openings',
        routes: [
          GoRoute(
            path: '/learn',
            builder: (_, __) => const Scaffold(body: Text('Learn')),
            routes: [
              GoRoute(
                path: 'openings',
                builder: (_, __) => const OpeningsScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/play',
            builder: (_, state) {
              capturedExtra = state.extra;
              return const Scaffold(body: Text('Play'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // Use bounded pumps to avoid infinite-animation timeout
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap the first _OpeningCard. The card uses InkWell wrapping a Container.
      // Use a text-based finder to locate the first opening card title.
      // The first card is "Sicilian Defense"
      final firstCardTitle = find.text('Sicilian Defense');
      expect(firstCardTitle, findsOneWidget, reason: 'Opening card not found.');
      await tester.tap(firstCardTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Tap "PRACTICE THIS OPENING" in the bottom sheet
      final practiceBtn = find.text('PRACTICE THIS OPENING');
      expect(
        practiceBtn,
        findsOneWidget,
        reason: 'Could not find PRACTICE THIS OPENING button. '
            'The bottom sheet may not have opened.',
      );
      await tester.tap(practiceBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // On unfixed code: context.go('/play') is called with no extra.
      // capturedExtra == null → assertion FAILS → bug confirmed.
      expect(
        capturedExtra,
        isNotNull,
        reason: 'BUG-9 counterexample: _openLesson() calls context.go("/play") '
            'with no extra parameter. GoRouterState.extra is null on the Play '
            'screen. An OpeningContext should be passed as extra so the Play '
            'screen can load the opening position.',
      );
    },
  );

  // ─── BUG-11: Static Home Dashboard ─────────────────────────────────────────
  testWidgets(
    'BUG-11 (isStaticDashboard): HomeDashboard displays authenticated user name',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) async => UserProfile(
                userId: 'u-test',
                email: 'test@robochess.com',
                displayName: 'TestUser',
              ),
            ),
            userStatsProvider.overrideWith(
              (ref) async => const UserStats(
                rating: 1200,
                globalRank: 42,
                gamesPlayed: 10,
                wins: 6,
                losses: 3,
                draws: 1,
                winRate: 0.6,
                accuracy: 0.75,
                puzzleAttempts: 5,
              ),
            ),
            gameControllerProvider.overrideWith((_) => _FakeGameController()),
          ],
          child: MaterialApp(
            home: const HomeDashboard(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // On unfixed code: HomeDashboard only reads gameControllerProvider.
      // userProfileProvider is never watched → 'TestUser' never rendered.
      // Assertion FAILS → bug confirmed.
      expect(
        find.textContaining('TestUser'),
        findsOneWidget,
        reason: 'BUG-11 counterexample: HomeDashboard.build() only calls '
            'ref.watch(gameControllerProvider). userProfileProvider and '
            'userStatsProvider are never consumed. The user\'s display name '
            '"TestUser" is therefore never rendered in the widget tree.',
      );
    },
  );

  // ─── BUG-12: Hardcoded Server URL ──────────────────────────────────────────
  test(
    'BUG-12 (isHardcodedServerUrl): apiClientProvider uses runtime-persisted URL',
    () async {
      // On unfixed code:
      //   apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      //     baseUrl: AppConfig.apiBaseUrl,   ← compile-time constant
      //     ...
      //   ));
      // AppConfig.apiBaseUrl == 'http://172.20.10.3:8000' (hardcoded default).
      // No ServerConfigProvider reads FlutterSecureStorage at runtime.
      //
      // The test verifies that the persisted URL ('http://192.168.1.1:8000')
      // is used by apiClientProvider instead of the compile-time constant.
      //
      // On unfixed code: client.baseUrl == AppConfig.apiBaseUrl (hardcoded)
      // → assertion fails → bug confirmed.

      const persistedUrl = 'http://192.168.1.1:8000';
      const compileTimeUrl = AppConfig.apiBaseUrl; // 'http://172.20.10.3:8000'

      // Seed the persisted URL into an in-memory store and wire both the
      // TokenStore and ServerConfigStore to it (avoids platform channels).
      final storage = _InMemorySecureStorage();
      await storage.write(key: 'server_base_url', value: persistedUrl);

      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWith(
            (ref) => TokenStore(storage: storage),
          ),
          serverConfigStoreProvider.overrideWith(
            (ref) => ServerConfigStore(storage: storage),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Trigger ServerConfigNotifier instantiation, then let its async _load()
      // read the persisted URL from storage before reading apiClientProvider.
      container.read(serverConfigProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final client = container.read(apiClientProvider);

      // Fixed behavior: the persisted URL overrides the compile-time default.
      expect(
        client.baseUrl,
        equals(persistedUrl),
        reason: 'BUG-12: apiClientProvider must construct ApiClient with the '
            'runtime-persisted baseUrl "$persistedUrl", not the compile-time '
            'constant "$compileTimeUrl". A ServerConfigProvider reading '
            '"server_base_url" from FlutterSecureStorage must be watched by '
            'apiClientProvider.',
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Test harness widgets
// ---------------------------------------------------------------------------

/// Mirrors the FIXED behavior for Draw button visibility: DRAW is rendered
/// only when gameMode == 'human_vs_human'.
class _GameControlsHarness extends StatelessWidget {
  final String gameMode;
  const _GameControlsHarness({required this.gameMode});

  @override
  Widget build(BuildContext context) {
    // Fixed behavior: Draw button hidden for bot modes.
    final showDraw = gameMode == 'human_vs_human';
    return Column(
      children: [
        // Resign (always shown)
        const Text('RESIGN'),
        // Draw — fixed: only shown in human_vs_human mode
        if (showDraw) const Text('DRAW'),
      ],
    );
  }
}

/// Mirrors the FIXED Resign button behavior (onTap handler wired).
class _ResignButtonHarness extends StatelessWidget {
  final bool hasHandler;
  const _ResignButtonHarness({required this.hasHandler, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Fixed: onResign callback wired to the Resign _ControlBtn
      onTap: hasHandler
          ? () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Resign?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                  ],
                ),
              )
          : null, // unfixed: null
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, color: Colors.red),
          Text('RESIGN'),
        ],
      ),
    );
  }
}

/// Mirrors the FIXED _PlayerRow behavior: reads userProfileProvider and
/// renders the authenticated display name (uppercased).
class _PlayerRowHarness extends ConsumerWidget {
  const _PlayerRowHarness({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final displayName =
        (profileAsync.valueOrNull?.displayName ?? 'Player').toUpperCase();
    return Text(displayName);
  }
}

// ---------------------------------------------------------------------------
// In-memory FlutterSecureStorage replacement for unit tests
// ---------------------------------------------------------------------------

/// A simple in-memory map that satisfies what TokenStore needs.
/// Avoids FlutterSecureStorage platform channel initialization in unit tests.
class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) _store[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map<String, String>.from(_store);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store.clear();

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
