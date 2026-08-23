/// A player as exposed by the social endpoints.
///
/// The backend deliberately never returns email addresses here, so this model
/// has no field for one.
class PublicUser {
  final String userId;
  final String displayName;
  final int? rating;

  const PublicUser({
    required this.userId,
    required this.displayName,
    this.rating,
  });

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Player',
      rating: _toIntOrNull(json['rating']),
    );
  }
}

/// One friendship row: an accepted friend, or a request in either direction.
class FriendModel {
  final String friendshipId;
  final String status;
  final PublicUser user;
  final bool requestedByMe;
  final DateTime? createdAt;

  const FriendModel({
    required this.friendshipId,
    required this.status,
    required this.user,
    required this.requestedByMe,
    this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  factory FriendModel.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return FriendModel(
      friendshipId: json['friendship_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      user: PublicUser.fromJson(
        rawUser is Map ? Map<String, dynamic>.from(rawUser) : const {},
      ),
      requestedByMe: json['requested_by_me'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

/// A user returned by search, annotated with the caller's relationship to them.
class UserSearchResult {
  final String userId;
  final String displayName;
  final int? rating;
  final String? friendStatus;
  final String? friendshipId;
  final bool requestedByMe;

  const UserSearchResult({
    required this.userId,
    required this.displayName,
    this.rating,
    this.friendStatus,
    this.friendshipId,
    this.requestedByMe = false,
  });

  bool get isFriend => friendStatus == 'accepted';
  bool get isPending => friendStatus == 'pending';

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Player',
      rating: _toIntOrNull(json['rating']),
      friendStatus: json['friend_status']?.toString(),
      friendshipId: json['friendship_id']?.toString(),
      requestedByMe: json['requested_by_me'] == true,
    );
  }
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}
