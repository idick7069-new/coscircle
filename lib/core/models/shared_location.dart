class SharedLocation {
  const SharedLocation({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.latitude,
    required this.longitude,
    required this.sharedAt,
    this.dayIndex = 1,
    this.publicCode = '',
    this.avatarUrl = '',
    this.characterName = '',
    this.workName = '',
    this.outfitImageUrl = '',
    this.interactionTags = const [],
    this.availableTime = '',
    this.presenceStatus = 'open',
    this.isMe = false,
    this.isFollowed = false,
    this.isCircleMember = false,
  });

  final String userId;
  final String nickname;
  final String role;
  final int dayIndex;
  final double latitude;
  final double longitude;
  final DateTime sharedAt;
  final String publicCode;
  final String avatarUrl;
  final String characterName;
  final String workName;
  final String outfitImageUrl;
  final List<String> interactionTags;
  final String availableTime;
  final String presenceStatus;
  final bool isMe;
  final bool isFollowed;
  final bool isCircleMember;

  factory SharedLocation.fromJson(Map<String, dynamic> json) {
    return SharedLocation(
      userId: json['userId'].toString(),
      nickname: json['nickname']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      dayIndex: _intValue(json['dayIndex'], fallback: 1),
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      sharedAt: DateTime.parse(json['sharedAt'].toString()),
      publicCode: json['publicCode']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      characterName: json['characterName']?.toString() ?? '',
      workName: json['workName']?.toString() ?? '',
      outfitImageUrl: json['outfitImageUrl']?.toString() ?? '',
      interactionTags: _stringList(json['interactionTags']),
      availableTime: json['availableTime']?.toString() ?? '',
      presenceStatus: json['presenceStatus']?.toString() ?? 'open',
      isMe: json['isMe'] == true || json['isMe'] == 1,
      isFollowed: json['isFollowed'] == true || json['isFollowed'] == 1,
      isCircleMember:
          json['isCircleMember'] == true || json['isCircleMember'] == 1,
    );
  }

  int minutesAgo(DateTime now) {
    return now.difference(sharedAt).inMinutes.clamp(0, 99999);
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
