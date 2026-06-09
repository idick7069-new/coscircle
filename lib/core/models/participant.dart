class EventParticipant {
  const EventParticipant({
    required this.userId,
    required this.nickname,
    required this.role,
    this.dayIndex = 1,
    this.publicCode = '',
    this.avatarUrl = '',
    this.facebookUrl = '',
    this.bio = '',
    this.characterName = '',
    this.workId = '',
    this.workName = '',
    this.outfitImageUrl = '',
    this.interactionTags = const [],
    this.availableTime = '',
    this.presenceStatus = 'open',
    this.message = '',
    this.isMe = false,
    this.isFollowed = false,
  });

  final String userId;
  final String nickname;
  final String role;
  final int dayIndex;
  final String publicCode;
  final String avatarUrl;
  final String facebookUrl;
  final String bio;
  final String characterName;
  final String workId;
  final String workName;
  final String outfitImageUrl;
  final List<String> interactionTags;
  final String availableTime;
  final String presenceStatus;
  final String message;
  final bool isMe;
  final bool isFollowed;

  factory EventParticipant.fromJson(Map<String, dynamic> json) {
    return EventParticipant(
      userId: json['userId'].toString(),
      nickname: json['nickname']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      dayIndex: _intValue(json['dayIndex'], fallback: 1),
      publicCode: json['publicCode']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      facebookUrl: json['facebookUrl']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      characterName: json['characterName']?.toString() ?? '',
      workId: json['workId']?.toString() ?? '',
      workName: json['workName']?.toString() ?? '',
      outfitImageUrl: json['outfitImageUrl']?.toString() ?? '',
      interactionTags: _stringList(json['interactionTags']),
      availableTime: json['availableTime']?.toString() ?? '',
      presenceStatus: json['presenceStatus']?.toString() ?? 'open',
      message: json['message']?.toString() ?? '',
      isMe: json['isMe'] == true || json['isMe'] == 1,
      isFollowed: json['isFollowed'] == true || json['isFollowed'] == 1,
    );
  }
}

int _intValue(Object? value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return const [];
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
