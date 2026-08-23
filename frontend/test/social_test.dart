// ignore_for_file: invalid_use_of_protected_member, subtype_of_sealed_class
//
// Coverage for the Play with Friends feature:
//   * model parsing for friends, search results, challenges and games
//   * the friends screen's list / empty / loading / error states
//   * contextual actions per tab (accept, decline, cancel, add, play)
//   * game list rendering for active and completed games

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:robochess_mobile/domain/models/challenge_model.dart';
import 'package:robochess_mobile/domain/models/friend_model.dart';
import 'package:robochess_mobile/domain/models/multiplayer_game_model.dart';
import 'package:robochess_mobile/presentation/providers/multiplayer_game_provider.dart';
import 'package:robochess_mobile/presentation/providers/social_provider.dart';
import 'package:robochess_mobile/presentation/screens/friends_screen.dart';
import 'package:robochess_mobile/presentation/screens/multiplayer_games_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeFriendsController extends StateNotifier<AsyncValue<FriendsState>>
    implements FriendsController {
  _FakeFriendsController(super.state);

  final List<String> calls = [];

  @override
  Future<void> load() async {}

  @override
  Future<void> sendRequest(String userId) async => calls.add('send:$userId');

  @override
  Future<void> acceptRequest(String id) async => calls.add('accept:$id');

  @override
  Future<void> rejectRequest(String id) async => calls.add('reject:$id');

  @override
  Future<void> cancelRequest(String id) async => calls.add('cancel:$id');

  @override
  Future<void> removeFriend(String userId) async => calls.add('remove:$userId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChallengesController
    extends StateNotifier<AsyncValue<ChallengesState>>
    implements ChallengesController {
  _FakeChallengesController(super.state);

  final List<String> calls = [];

  @override
  Stream<String> get gameStarted => const Stream<String>.empty();

  @override
  Future<void> load() async {}

  @override
  Future<String> accept(String challengeId, {String surface = 'app'}) async {
    calls.add('accept:$challengeId');
    return 'game-1';
  }

  @override
  Future<void> reject(String challengeId) async =>
      calls.add('reject:$challengeId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGameListController
    extends StateNotifier<AsyncValue<List<MultiplayerGame>>>
    implements GameListController {
  _FakeGameListController(super.state);

  @override
  Future<void> load() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

FriendModel _friend(String name, {String status = 'accepted', bool mine = false}) {
  return FriendModel.fromJson({
    'friendship_id': 'f-$name',
    'status': status,
    'requested_by_me': mine,
    'user': {'user_id': 'u-$name', 'display_name': name, 'rating': 1200},
  });
}

MultiplayerGame _game({
  required String status,
  bool yourTurn = false,
  String? yourResult,
  String? endReason,
}) {
  return MultiplayerGame.fromJson({
    'game_id': 'g-1',
    'current_fen': '',
    'status': status,
    'game_version': 3,
    'your_turn': yourTurn,
    'your_color': 'white',
    'your_result': yourResult,
    'end_reason': endReason,
    'last_move': 'e2e4',
    'opponent': {'user_id': 'u-bob', 'display_name': 'Bob', 'rating': 1300},
  });
}

Widget _wrap(Widget child, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(
          path: '/play/games',
          builder: (_, __) => const Scaffold(body: Text('games route'))),
      GoRoute(
          path: '/play/friends',
          builder: (_, __) => const Scaffold(body: Text('friends route'))),
      GoRoute(
          path: '/play/game/:gameId',
          builder: (_, __) => const Scaffold(body: Text('game route'))),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

List<Override> _overrides({
  AsyncValue<FriendsState>? friends,
  AsyncValue<ChallengesState>? challenges,
  _FakeFriendsController? friendsController,
  _FakeChallengesController? challengesController,
}) {
  return [
    friendsProvider.overrideWith((_) =>
        friendsController ??
        _FakeFriendsController(friends ?? const AsyncValue.data(FriendsState()))),
    challengesProvider.overrideWith((_) =>
        challengesController ??
        _FakeChallengesController(
            challenges ?? const AsyncValue.data(ChallengesState()))),
  ];
}

void main() {
  group('model parsing', () {
    test('FriendModel reads the nested user and direction flag', () {
      final friend = _friend('Alice', status: 'pending', mine: true);
      expect(friend.friendshipId, 'f-Alice');
      expect(friend.user.displayName, 'Alice');
      expect(friend.user.rating, 1200);
      expect(friend.requestedByMe, isTrue);
      expect(friend.isPending, isTrue);
      expect(friend.isAccepted, isFalse);
    });

    test('FriendModel survives a missing user object', () {
      final friend = FriendModel.fromJson({'friendship_id': 'f1'});
      expect(friend.user.displayName, 'Player',
          reason: 'a missing user must not crash the list');
      expect(friend.status, 'pending');
    });

    test('UserSearchResult exposes relationship state', () {
      final result = UserSearchResult.fromJson({
        'user_id': 'u1',
        'display_name': 'Bob',
        'friend_status': 'accepted',
      });
      expect(result.isFriend, isTrue);
      expect(result.isPending, isFalse);
    });

    test('ChallengeModel flags an elapsed deadline', () {
      final expired = ChallengeModel.fromJson({
        'challenge_id': 'c1',
        'status': 'pending',
        'expires_at':
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
        'opponent': {'user_id': 'u1', 'display_name': 'Bob'},
      });
      expect(expired.hasExpired, isTrue);

      final live = ChallengeModel.fromJson({
        'challenge_id': 'c2',
        'status': 'pending',
        'expires_at':
            DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
        'opponent': {'user_id': 'u1', 'display_name': 'Bob'},
      });
      expect(live.hasExpired, isFalse);
    });

    test('MultiplayerGame maps clocks to the right player', () {
      final game = MultiplayerGame.fromJson({
        'game_id': 'g1',
        'current_fen': 'fen',
        'status': 'active',
        'opponent': {'user_id': 'u-bob', 'display_name': 'Bob'},
        'clocks': {
          'u-me': {'remaining_ms': 45000},
          'u-bob': {'remaining_ms': 30000},
        },
      });
      expect(game.yourRemainingMs, 45000);
      expect(game.opponentRemainingMs, 30000);
      expect(game.hasClock, isTrue);
    });

    test('MultiplayerGame identifies who offered a draw', () {
      final fromOpponent = MultiplayerGame.fromJson({
        'game_id': 'g1',
        'status': 'active',
        'draw_offer_by': 'u-bob',
        'opponent': {'user_id': 'u-bob', 'display_name': 'Bob'},
      });
      expect(fromOpponent.drawOfferedByOpponent, isTrue);
      expect(fromOpponent.drawOfferedByMe, isFalse);

      final fromMe = MultiplayerGame.fromJson({
        'game_id': 'g1',
        'status': 'active',
        'draw_offer_by': 'u-me',
        'opponent': {'user_id': 'u-bob', 'display_name': 'Bob'},
      });
      expect(fromMe.drawOfferedByMe, isTrue);
      expect(fromMe.drawOfferedByOpponent, isFalse);
    });

    test('a board-backed player is distinguished from an app player', () {
      MultiplayerGame withSurface(String surface) =>
          MultiplayerGame.fromJson({
            'game_id': 'g1',
            'status': 'active',
            'your_surface': surface,
            'opponent': {'user_id': 'u1', 'display_name': 'Bob'},
          });
      expect(withSurface('app').playsOnBoard, isFalse);
      expect(withSurface('board-7').playsOnBoard, isTrue);
    });
  });

  group('FriendsScreen', () {
    testWidgets('shows a spinner while loading', (tester) async {
      await tester.pumpWidget(_wrap(const FriendsScreen(),
          _overrides(friends: const AsyncValue.loading())));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('guides the user when they have no friends yet', (tester) async {
      await tester.pumpWidget(_wrap(const FriendsScreen(), _overrides()));
      await tester.pump();
      expect(find.textContaining('No friends yet'), findsOneWidget);
    });

    testWidgets('reports a load failure without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        const FriendsScreen(),
        _overrides(friends: AsyncValue.error('boom', StackTrace.empty)),
      ));
      await tester.pump();
      expect(find.textContaining('Could not load your friends'), findsOneWidget);
    });

    testWidgets('lists friends with a play action', (tester) async {
      await tester.pumpWidget(_wrap(
        const FriendsScreen(),
        _overrides(
          friends: AsyncValue.data(FriendsState(friends: [_friend('Alice')])),
        ),
      ));
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('PLAY'), findsOneWidget);
    });

    testWidgets('incoming requests can be accepted', (tester) async {
      final controller = _FakeFriendsController(
        AsyncValue.data(FriendsState(
            incoming: [_friend('Carol', status: 'pending')])),
      );
      await tester.pumpWidget(_wrap(
          const FriendsScreen(), _overrides(friendsController: controller)));
      await tester.pump();

      await tester.tap(find.text('INBOX'));
      await tester.pump();
      expect(find.text('Carol'), findsOneWidget);

      await tester.tap(find.text('ACCEPT'));
      await tester.pump();
      expect(controller.calls, contains('accept:f-Carol'));
    });

    testWidgets('incoming requests can be declined', (tester) async {
      final controller = _FakeFriendsController(
        AsyncValue.data(FriendsState(
            incoming: [_friend('Carol', status: 'pending')])),
      );
      await tester.pumpWidget(_wrap(
          const FriendsScreen(), _overrides(friendsController: controller)));
      await tester.pump();

      await tester.tap(find.text('INBOX'));
      await tester.pump();
      await tester.tap(find.text('DECLINE'));
      await tester.pump();
      expect(controller.calls, contains('reject:f-Carol'));
    });

    testWidgets('a sent request can be cancelled', (tester) async {
      final controller = _FakeFriendsController(
        AsyncValue.data(FriendsState(
            outgoing: [_friend('Dave', status: 'pending', mine: true)])),
      );
      await tester.pumpWidget(_wrap(
          const FriendsScreen(), _overrides(friendsController: controller)));
      await tester.pump();

      await tester.tap(find.text('SENT'));
      await tester.pump();
      expect(find.text('Request pending'), findsOneWidget);

      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      expect(controller.calls, contains('cancel:f-Dave'));
    });

    testWidgets('the inbox tab carries a badge for pending requests',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const FriendsScreen(),
        _overrides(
          friends: AsyncValue.data(FriendsState(
              incoming: [_friend('Carol', status: 'pending')])),
        ),
      ));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('search prompts for a longer query', (tester) async {
      await tester.pumpWidget(_wrap(const FriendsScreen(), _overrides()));
      await tester.pump();

      await tester.tap(find.text('SEARCH'));
      await tester.pump();
      expect(find.textContaining('at least 2 characters'), findsOneWidget);
    });

    testWidgets('an incoming challenge offers accept and decline',
        (tester) async {
      final challenge = ChallengeModel.fromJson({
        'challenge_id': 'c1',
        'status': 'pending',
        'outgoing': false,
        'expires_at':
            DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
        'opponent': {'user_id': 'u-bob', 'display_name': 'Bob'},
      });
      final controller = _FakeChallengesController(
          AsyncValue.data(ChallengesState(incoming: [challenge])));

      await tester.pumpWidget(_wrap(
          const FriendsScreen(), _overrides(challengesController: controller)));
      await tester.pump();

      expect(find.text('GAME CHALLENGES'), findsOneWidget);
      await tester.tap(find.text('ACCEPT'));
      await tester.pump();
      expect(controller.calls, contains('accept:c1'));
    });

    testWidgets('an expired challenge cannot be accepted', (tester) async {
      final expired = ChallengeModel.fromJson({
        'challenge_id': 'c2',
        'status': 'pending',
        'outgoing': false,
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'opponent': {'user_id': 'u-bob', 'display_name': 'Bob'},
      });
      await tester.pumpWidget(_wrap(
        const FriendsScreen(),
        _overrides(challenges: AsyncValue.data(ChallengesState(incoming: [expired]))),
      ));
      await tester.pump();

      expect(find.text('Challenge expired'), findsOneWidget);
      expect(find.text('ACCEPT'), findsNothing,
          reason: 'an expired challenge must not be acceptable');
      expect(find.text('DECLINE'), findsOneWidget);
    });
  });

  group('MultiplayerGamesScreen', () {
    List<Override> gameOverrides(
      AsyncValue<List<MultiplayerGame>> active, {
      AsyncValue<List<MultiplayerGame>>? history,
    }) =>
        [
          activeGamesProvider.overrideWith((_) => _FakeGameListController(active)),
          gameHistoryProvider.overrideWith(
              (_) => _FakeGameListController(history ?? const AsyncValue.data([]))),
        ];

    testWidgets('prompts to start a game when none are active', (tester) async {
      await tester.pumpWidget(_wrap(const MultiplayerGamesScreen(),
          gameOverrides(const AsyncValue.data([]))));
      await tester.pump();
      expect(find.textContaining('No games in progress'), findsOneWidget);
    });

    testWidgets('an active game shows whose move it is', (tester) async {
      await tester.pumpWidget(_wrap(
        const MultiplayerGamesScreen(),
        gameOverrides(AsyncValue.data([_game(status: 'active', yourTurn: true)])),
      ));
      await tester.pump();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Your move'), findsOneWidget);
      expect(find.text('CONTINUE'), findsOneWidget);
    });

    testWidgets('a waiting game does not claim it is your move',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const MultiplayerGamesScreen(),
        gameOverrides(AsyncValue.data([_game(status: 'active')])),
      ));
      await tester.pump();
      expect(find.text('Waiting for opponent'), findsOneWidget);
    });

    testWidgets('history explains how a game ended', (tester) async {
      await tester.pumpWidget(_wrap(
        const MultiplayerGamesScreen(),
        gameOverrides(
          const AsyncValue.data([]),
          history: AsyncValue.data([
            _game(status: 'completed', yourResult: 'won', endReason: 'checkmate')
          ]),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('HISTORY'));
      await tester.pump();
      expect(find.text('You won by checkmate'), findsOneWidget);
      expect(find.text('REVIEW'), findsOneWidget);
    });

    testWidgets('reports a load failure without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        const MultiplayerGamesScreen(),
        gameOverrides(AsyncValue.error('boom', StackTrace.empty)),
      ));
      await tester.pump();
      expect(find.textContaining('Could not load your games'), findsOneWidget);
    });
  });
}
