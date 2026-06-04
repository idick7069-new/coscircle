class CircleGroup {
  const CircleGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.inviteUrl,
    required this.memberCount,
    required this.isOwner,
    this.description = '',
    this.members = const [],
  });

  final String id;
  final String name;
  final String inviteCode;
  final String inviteUrl;
  final int memberCount;
  final bool isOwner;
  final String description;
  final List<CircleMember> members;

  factory CircleGroup.fromJson(Map<String, dynamic> json) {
    return CircleGroup(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      inviteCode: json['inviteCode']?.toString() ?? '',
      inviteUrl: json['inviteUrl']?.toString() ?? '',
      memberCount: _asInt(json['memberCount']),
      isOwner: json['isOwner'] == true || json['isOwner'] == 1,
      description: json['description']?.toString() ?? '',
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((row) => CircleMember.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CircleMember {
  const CircleMember({
    required this.userId,
    required this.publicCode,
    required this.nickname,
    this.avatarUrl = '',
    this.isOwner = false,
  });

  final String userId;
  final String publicCode;
  final String nickname;
  final String avatarUrl;
  final bool isOwner;

  factory CircleMember.fromJson(Map<String, dynamic> json) {
    return CircleMember(
      userId: json['userId'].toString(),
      publicCode: json['publicCode']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      isOwner: json['isOwner'] == true || json['isOwner'] == 1,
    );
  }
}

class FollowedUser {
  const FollowedUser({
    required this.userId,
    required this.publicCode,
    required this.nickname,
    this.avatarUrl = '',
    this.bio = '',
    this.followedAt,
  });

  final String userId;
  final String publicCode;
  final String nickname;
  final String avatarUrl;
  final String bio;
  final DateTime? followedAt;

  factory FollowedUser.fromJson(Map<String, dynamic> json) {
    final followedAtText = json['followedAt']?.toString() ?? '';
    return FollowedUser(
      userId: json['userId'].toString(),
      publicCode: json['publicCode']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      followedAt: followedAtText.isEmpty
          ? null
          : DateTime.tryParse(followedAtText),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.parse(value.toString());
}
