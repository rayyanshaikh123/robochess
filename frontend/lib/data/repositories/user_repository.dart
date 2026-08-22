import '../datasources/user_remote.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/user_stats.dart';

class UserRepository {
  final UserRemoteDataSource _remote;

  UserRepository(this._remote);

  Future<UserProfile> me() {
    return _remote.me();
  }

  Future<UserStats> stats() {
    return _remote.stats();
  }

  Future<UserProfile> updateProfile({required String displayName}) {
    return _remote.updateProfile(displayName: displayName);
  }
}
