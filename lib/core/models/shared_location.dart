class SharedLocation {
  const SharedLocation({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.latitude,
    required this.longitude,
    required this.sharedAt,
    this.avatarUrl = '',
    this.characterName = '',
    this.outfitImageUrl = '',
    this.isMe = false,
    this.isFollowed = false,
    this.isCircleMember = false,
  });

  final String userId;
  final String nickname;
  final String role;
  final double latitude;
  final double longitude;
  final DateTime sharedAt;
  final String avatarUrl;
  final String characterName;
  final String outfitImageUrl;
  final bool isMe;
  final bool isFollowed;
  final bool isCircleMember;

  factory SharedLocation.fromJson(Map<String, dynamic> json) {
    return SharedLocation(
      userId: json['userId'].toString(),
      nickname: json['nickname']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      sharedAt: DateTime.parse(json['sharedAt'].toString()),
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      characterName: json['characterName']?.toString() ?? '',
      outfitImageUrl: json['outfitImageUrl']?.toString() ?? '',
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
