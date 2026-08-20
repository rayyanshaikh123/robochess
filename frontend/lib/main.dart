import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'presentation/theme/app_theme.dart';
import 'presentation/screens/main_scaffold.dart';
import 'presentation/screens/home_dashboard.dart';
import 'presentation/screens/play_screen.dart';
import 'presentation/screens/analysis_screen.dart';
import 'presentation/screens/learn_section.dart';
import 'presentation/screens/openings_screen.dart';
import 'presentation/screens/puzzle_solve_screen.dart';
import 'presentation/screens/cross_connect.dart';
import 'presentation/screens/profile_settings.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/register_screen.dart';
import 'presentation/screens/board_link_screen.dart';
import 'presentation/screens/ble_provision_screen.dart';
import 'presentation/screens/board_details_screen.dart';
import 'presentation/providers/session_provider.dart';
import 'domain/models/puzzle_model.dart';
import 'domain/models/auth_session.dart';

void main() {
  runApp(
    const ProviderScope(
      child: RoboChessApp(),
    ),
  );
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter _buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/login',
    navigatorKey: _rootNavigatorKey,
    redirect: (context, state) {
      final currentSession = ref.read(sessionProvider).valueOrNull;
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (currentSession == null && !loggingIn) {
        return '/login';
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeDashboard(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/play',
                builder: (context, state) => const PlayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analysis',
                builder: (context, state) {
                  final gameId = state.uri.queryParameters['game_id'];
                  return AnalysisScreen(gameId: gameId);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/learn',
                builder: (context, state) => const LearnSection(),
              ),
              GoRoute(
                path: '/learn/openings',
                builder: (context, state) => const OpeningsScreen(),
              ),
              GoRoute(
                path: '/learn/puzzle/:puzzleId',
                builder: (context, state) {
                  final extra = state.extra;
                  final puzzleId = state.pathParameters['puzzleId'] ?? '';
                  final puzzle = extra is PuzzleModel ? extra : null;
                  return PuzzleSolveScreen(puzzleId: puzzleId, puzzle: puzzle);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/connect',
                builder: (context, state) => const CrossConnect(),
              ),
              GoRoute(
                path: '/connect/link',
                builder: (context, state) => const BoardLinkScreen(),
              ),
              GoRoute(
                path: '/connect/ble',
                builder: (context, state) => const BleProvisionScreen(),
              ),
              GoRoute(
                path: '/connect/board/:deviceId',
                builder: (context, state) => BoardDetailsScreen(
                    deviceId: state.pathParameters['deviceId'] ?? ''),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileSettings(),
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
  late final GoRouter _router;
  late final ProviderSubscription<AsyncValue<AuthSession?>> _sessionSub;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(ref);
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
