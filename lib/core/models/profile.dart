import 'work.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    this.publicCode = '',
    this.avatarUrl = '',
    this.facebookUrl = '',
    this.bio = '',
    this.pitWorks = const [],
  });

  final String id;
  final String nickname;
  final String publicCode;
  final String avatarUrl;
  final String facebookUrl;
  final String bio;
  final List<WorkTag> pitWorks;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      publicCode: json['publicCode']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      facebookUrl: json['facebookUrl']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      pitWorks: (json['pitWorks'] as List<dynamic>? ?? const [])
          .map((row) => WorkTag.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nickname': nickname,
      'avatarUrl': avatarUrl,
      'facebookUrl': facebookUrl,
      'bio': bio,
      'pitWorkIds': pitWorks.map((work) => work.id).toList(),
    };
  }

  UserProfile copyWith({
    String? nickname,
    String? publicCode,
    String? avatarUrl,
    String? facebookUrl,
    String? bio,
    List<WorkTag>? pitWorks,
  }) {
    return UserProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      publicCode: publicCode ?? this.publicCode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      facebookUrl: facebookUrl ?? this.facebookUrl,
      bio: bio ?? this.bio,
      pitWorks: pitWorks ?? this.pitWorks,
    );
  }
}
