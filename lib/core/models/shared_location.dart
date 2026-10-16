class SharedLocation {
  const SharedLocation({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.latitude,
    required this.longitude,
    required this.sharedAt,
    this.dayIndex = 1,
    this.visibility = 'circle',
    this.expiresAt,
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
    this.isFriend = false,
  });

  final String userId;
  final String nickname;
  final String role;
  final int dayIndex;
  final double latitude;
  final double longitude;
  final DateTime sharedAt;
  final String visibility;
  final DateTime? expiresAt;
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
  final bool isFriend;

  factory SharedLocation.fromJson(Map<String, dynamic> json) {
    return SharedLocation(
      userId: json['userId'].toString(),
      nickname: json['nickname']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      dayIndex: _intValue(json['dayIndex'], fallback: 1),
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      sharedAt:
          _epochDateTime(json['sharedAtEpoch']) ??
          DateTime.parse(json['sharedAt'].toString()),
      visibility: json['visibility']?.toString() ?? 'circle',
      expiresAt:
          _epochDateTime(json['expiresAtEpoch']) ??
          _nullableDateTime(json['expiresAt']),
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
      isFriend: json['isFriend'] == true || json['isFriend'] == 1,
      isCircleMember:
          json['isCircleMember'] == true || json['isCircleMember'] == 1,
    );
  }

  int minutesAgo(DateTime now) {
    return now.difference(sharedAt).inMinutes.clamp(0, 99999);
  }

  int? minutesUntilExpiry(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return null;
    return expiry.difference(now).inMinutes.clamp(0, 99999);
  }
}

DateTime? _epochDateTime(Object? value) {
  final seconds = num.tryParse(value?.toString() ?? '');
  return seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
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

DateTime? _nullableDateTime(Object? value) {
  final text = value?.toString() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}
