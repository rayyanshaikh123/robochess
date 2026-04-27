import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/user_remote.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/user_stats.dart';
import 'session_provider.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(UserRemoteDataSource(ref.read(apiClientProvider)));
});

final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  return ref.read(userRepositoryProvider).me();
});

final userStatsProvider = FutureProvider<UserStats>((ref) async {
  return ref.read(userRepositoryProvider).stats();
});
