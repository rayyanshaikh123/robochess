import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/user_remote.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/user_stats.dart';
import 'session_provider.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(UserRemoteDataSource(ref.watch(apiClientProvider)));
});

/// Re-runs dependent fetches whenever the signed-in session changes, so a
/// result cached for a previous (or expired) login is never shown after a new
/// login.
final _sessionTokenProvider = Provider<String?>((ref) {
  return ref.watch(
      sessionProvider.select((session) => session.valueOrNull?.accessToken));
});

final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  ref.watch(_sessionTokenProvider);
  return ref.watch(userRepositoryProvider).me();
});

// autoDispose: stats are refetched each time a screen showing them opens, so
// results from games finished since then appear.
final userStatsProvider = FutureProvider.autoDispose<UserStats>((ref) async {
  ref.watch(_sessionTokenProvider);
  return ref.watch(userRepositoryProvider).stats();
});
