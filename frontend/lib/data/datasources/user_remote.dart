import '../../core/network/api_client.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/user_stats.dart';

class UserRemoteDataSource {
  final ApiClient _client;

  UserRemoteDataSource(this._client);

  Future<UserProfile> me() async {
    final data = await _client.getJson('/auth/me');
    return UserProfile.fromJson(data);
  }

  Future<UserStats> stats() async {
    final data = await _client.getJson('/auth/stats');
    return UserStats.fromJson(data);
  }

  Future<UserProfile> updateProfile({required String displayName}) async {
    final data = await _client.patchJson('/auth/me', body: {
      'display_name': displayName,
    });
    return UserProfile.fromJson(data);
  }
}
