import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'presentation/theme/app_theme.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/main_scaffold.dart';
import 'presentation/screens/home_dashboard.dart';
import 'presentation/screens/play_screen.dart';
import 'presentation/screens/analysis_screen.dart';
import 'presentation/screens/learn_section.dart';
import 'presentation/screens/openings_screen.dart';
import 'presentation/screens/puzzle_solve_screen.dart';
import 'presentation/screens/cross_connect.dart';
import 'presentation/screens/profile_settings.dart';
import 'presentation/screens/register_screen.dart';
import 'presentation/screens/board_link_screen.dart';
import 'presentation/screens/ble_provision_screen.dart';
import 'presentation/screens/board_details_screen.dart';
import 'presentation/screens/local_board_screen.dart';
import 'presentation/screens/lesson_track_screen.dart';
import 'presentation/providers/session_provider.dart';
import 'domain/models/puzzle_model.dart';
import 'domain/models/auth_session.dart';

void main() {
  runApp(const ProviderScope(child: RoboChessApp()));
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter _buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/login',
    navigatorKey: _rootNavigatorKey,
    redirect: (context, state) {
      final session = ref.read(sessionProvider).valueOrNull;
      final isLogin = state.matchedLocation == '/login' || state.matchedLocation == '/register';
      final isLocal = state.matchedLocation == '/local';

      if (session == null && !isLogin && !isLocal) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/local', builder: (c, s) => const LocalBoardScreen()),
      GoRoute(path: '/profile', builder: (c, s) => const ProfileSettings()),
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => MainScaffold(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (c, s) => const HomeDashboard())]),
          StatefulShellBranch(routes: [GoRoute(path: '/play', builder: (c, s) => const PlayScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/analysis', builder: (c, s) => AnalysisScreen(gameId: s.uri.queryParameters['game_id']))
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/learn', builder: (c, s) => const LearnSection()),
            GoRoute(path: '/learn/openings', builder: (c, s) => const OpeningsScreen()),
            GoRoute(
              path: '/learn/endgames',
              builder: (c, s) => const LessonTrackScreen(
                title: 'Endgame Strategy',
                description: 'Convert small advantages into clean, repeatable wins.',
                accent: Color(0xFFA2E7FF),
                lessons: [
                  LessonItem(title: 'Opposition', summary: 'Use king opposition to force the defending king away from the promotion square.', objective: 'win the key king position'),
                  LessonItem(title: 'Rook Behind the Pawn', summary: 'Place the rook behind passed pawns and use checks from the side.', objective: 'support a passed pawn'),
                  LessonItem(title: 'Basic Mating Nets', summary: 'Coordinate king and queen or rook without stalemating the opponent.', objective: 'finish accurately'),
                ],
              ),
            ),
            GoRoute(
              path: '/learn/tactics',
              builder: (c, s) => const LessonTrackScreen(
                title: 'Tactical Drills',
                description: 'Train the calculation patterns that decide practical games.',
                accent: Color(0xFF97D77E),
                lessons: [
                  LessonItem(title: 'Checks, Captures, Threats', summary: 'Scan forcing moves first and reduce the position to concrete candidates.', objective: 'find the forcing move'),
                  LessonItem(title: 'Pins and Skewers', summary: 'Exploit overloaded defenders and pieces aligned with a valuable target.', objective: 'win material cleanly'),
                  LessonItem(title: 'Discovered Attacks', summary: 'Move one piece to reveal a second attack and create a double threat.', objective: 'spot the hidden line'),
                ],
              ),
            ),
            GoRoute(
              path: '/learn/puzzle/:puzzleId',
              builder: (c, s) => PuzzleSolveScreen(
                puzzleId: s.pathParameters['puzzleId'] ?? '',
                puzzle: s.extra is PuzzleModel ? s.extra as PuzzleModel : null,
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/connect', builder: (c, s) => const CrossConnect()),
            GoRoute(path: '/connect/link', builder: (c, s) => const BoardLinkScreen()),
            GoRoute(path: '/connect/ble', builder: (c, s) => const BleProvisionScreen()),
            GoRoute(path: '/connect/board/:deviceId', builder: (c, s) => BoardDetailsScreen(deviceId: s.pathParameters['deviceId'] ?? '')),
          ]),
        ],
      ),
    ],
  );
}

class RoboChessApp extends ConsumerStatefulWidget {
  const RoboChessApp({super.key});

  @override
  ConsumerState<RoboChessApp> createState() => _RoboChessAppState();
}

class _RoboChessAppState extends ConsumerState<RoboChessApp> {
  late final GoRouter _router = _buildRouter(ref);
  late final ProviderSubscription<AsyncValue<AuthSession?>> _sessionSub;

  @override
  void initState() {
    super.initState();
    _sessionSub =
        ref.listenManual<AsyncValue<AuthSession?>>(sessionProvider, (_, __) {
      _router.refresh();
    });
  }

  @override
  void dispose() {
    _sessionSub.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RoboChess Mobile',
      theme: AppTheme.darkTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
