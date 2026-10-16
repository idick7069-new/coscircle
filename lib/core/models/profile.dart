import 'work.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    this.publicCode = '',
    this.isAdmin = false,
    this.isFollowed = false,
    this.isMe = false,
    this.avatarUrl = '',
    this.facebookUrl = '',
    this.bio = '',
    this.pitWorks = const [],
    this.deepPitWorks = const [],
    this.shallowPitWorks = const [],
    this.age = '',
    this.regions = const [],
    this.travelRegions = const [],
    this.travelSameRegion = false,
    this.landmine = '',
    this.gender = 'private',
    this.profileRoles = const [],
    this.otherPhotoUrls = const [],
    this.bookingVisibility = 'public',
    this.onboardingCompleted = false,
  });

  final String id;
  final String nickname;
  final String publicCode;
  final bool isAdmin;
  final bool isFollowed;
  final bool isMe;
  final String avatarUrl;
  final String facebookUrl;
  final String bio;
  final List<WorkTag> pitWorks;
  final List<WorkTag> deepPitWorks;
  final List<WorkTag> shallowPitWorks;
  final String age;
  final List<String> regions;
  final List<String> travelRegions;
  final bool travelSameRegion;
  final String landmine;
  final String gender;
  final List<String> profileRoles;
  final List<String> otherPhotoUrls;
  final String bookingVisibility;
  final bool onboardingCompleted;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final pitWorks = (json['pitWorks'] as List<dynamic>? ?? const [])
        .map((row) => WorkTag.fromJson(row as Map<String, dynamic>))
        .toList();
    final deepPitWorks = (json['deepPitWorks'] as List<dynamic>? ?? const [])
        .map((row) => WorkTag.fromJson(row as Map<String, dynamic>))
        .toList();
    final shallowPitWorks =
        (json['shallowPitWorks'] as List<dynamic>? ?? const [])
            .map((row) => WorkTag.fromJson(row as Map<String, dynamic>))
            .toList();
    return UserProfile(
      id: json['id']?.toString() ?? '',
      onboardingCompleted:
          json['onboardingCompleted'] == true ||
          json['onboardingCompleted'] == 1,
      nickname: json['nickname']?.toString() ?? '',
      publicCode: json['publicCode']?.toString() ?? '',
      isAdmin: json['isAdmin'] == true || json['isAdmin'] == 1,
      isFollowed: json['isFollowed'] == true || json['isFollowed'] == 1,
      isMe: json['isMe'] == true || json['isMe'] == 1,
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      facebookUrl: json['facebookUrl']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      pitWorks: pitWorks,
      deepPitWorks: deepPitWorks.isEmpty && shallowPitWorks.isEmpty
          ? pitWorks
          : deepPitWorks,
      shallowPitWorks: shallowPitWorks,
      age: json['age']?.toString() ?? '',
      regions: (json['regions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      travelRegions: (json['travelRegions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      travelSameRegion:
          json['travelSameRegion'] == true || json['travelSameRegion'] == 1,
      landmine: json['landmine']?.toString() ?? '',
      gender: json['gender']?.toString() ?? 'private',
      profileRoles: (json['profileRoles'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => _validProfileRoles.contains(item))
          .toList(),
      otherPhotoUrls: (json['otherPhotoUrls'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .take(3)
          .toList(),
      bookingVisibility: json['bookingVisibility']?.toString() == 'circle'
          ? 'circle'
          : 'public',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nickname': nickname,
      'onboardingCompleted': onboardingCompleted,
      'avatarUrl': avatarUrl,
      'facebookUrl': facebookUrl,
      'bio': bio,
      'pitWorkIds': pitWorks.map((work) => work.id).toList(),
      'deepPitWorkIds': deepPitWorks.map((work) => work.id).toList(),
      'shallowPitWorkIds': shallowPitWorks.map((work) => work.id).toList(),
      'age': age,
      'regions': regions,
      'travelRegions': travelRegions,
      'travelSameRegion': travelSameRegion,
      'landmine': landmine,
      'gender': gender,
      'profileRoles': profileRoles,
      'otherPhotoUrls': otherPhotoUrls.take(3).toList(),
      'bookingVisibility': bookingVisibility,
    };
  }

  UserProfile copyWith({
    String? nickname,
    bool? onboardingCompleted,
    String? publicCode,
    bool? isAdmin,
    bool? isFollowed,
    String? avatarUrl,
    String? facebookUrl,
    String? bio,
    List<WorkTag>? pitWorks,
    List<WorkTag>? deepPitWorks,
    List<WorkTag>? shallowPitWorks,
    String? age,
    List<String>? regions,
    List<String>? travelRegions,
    bool? travelSameRegion,
    String? landmine,
    String? gender,
    List<String>? profileRoles,
    List<String>? otherPhotoUrls,
    String? bookingVisibility,
  }) {
    final nextDeepPitWorks = deepPitWorks ?? this.deepPitWorks;
    final nextShallowPitWorks = shallowPitWorks ?? this.shallowPitWorks;
    return UserProfile(
      id: id,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      nickname: nickname ?? this.nickname,
      publicCode: publicCode ?? this.publicCode,
      isAdmin: isAdmin ?? this.isAdmin,
      isFollowed: isFollowed ?? this.isFollowed,
      isMe: isMe,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      facebookUrl: facebookUrl ?? this.facebookUrl,
      bio: bio ?? this.bio,
      pitWorks: pitWorks ?? [...nextDeepPitWorks, ...nextShallowPitWorks],
      deepPitWorks: nextDeepPitWorks,
      shallowPitWorks: nextShallowPitWorks,
      age: age ?? this.age,
      regions: regions ?? this.regions,
      travelRegions: travelRegions ?? this.travelRegions,
      travelSameRegion: travelSameRegion ?? this.travelSameRegion,
      landmine: landmine ?? this.landmine,
      gender: gender ?? this.gender,
      profileRoles: profileRoles ?? this.profileRoles,
      otherPhotoUrls: otherPhotoUrls ?? this.otherPhotoUrls,
      bookingVisibility: bookingVisibility ?? this.bookingVisibility,
    );
  }
}

const _validProfileRoles = {'coser', 'photographer', 'manager', 'self'};
