class UserProfile {
  final String userId;
  final String email;
  final String displayName;
  final String? createdAt;

  UserProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Player',
      createdAt: json['created_at']?.toString(),
    );
  }
}
