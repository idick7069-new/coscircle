class BookingFollower {
  const BookingFollower({
    required this.userId,
    required this.nickname,
    this.publicCode = '',
    this.avatarUrl = '',
    this.followedAt = '',
  });

  final String userId;
  final String nickname;
  final String publicCode;
  final String avatarUrl;
  final String followedAt;

  factory BookingFollower.fromJson(Map<String, dynamic> json) {
    return BookingFollower(
      userId: json['userId']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      publicCode: json['publicCode']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      followedAt: json['followedAt']?.toString() ?? '',
    );
  }
}

class BookingFollowerGroup {
  const BookingFollowerGroup({
    required this.bookingId,
    required this.eventId,
    required this.eventName,
    required this.startDate,
    required this.endDate,
    required this.dayIndex,
    required this.role,
    this.followers = const [],
  });

  final String bookingId;
  final String eventId;
  final String eventName;
  final DateTime startDate;
  final DateTime endDate;
  final int dayIndex;
  final String role;
  final List<BookingFollower> followers;

  factory BookingFollowerGroup.fromJson(Map<String, dynamic> json) {
    return BookingFollowerGroup(
      bookingId: json['bookingId']?.toString() ?? '',
      eventId: json['eventId']?.toString() ?? '',
      eventName: json['eventName']?.toString() ?? '',
      startDate: DateTime.tryParse(json['startDate']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endDate: DateTime.tryParse(json['endDate']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dayIndex: int.tryParse(json['dayIndex']?.toString() ?? '') ?? 1,
      role: json['role']?.toString() ?? '',
      followers: (json['followers'] as List<dynamic>? ?? const [])
          .map((row) => BookingFollower.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.nickname,
    this.publicCode = '',
    this.avatarUrl = '',
    this.blockedAt = '',
  });

  final String userId;
  final String nickname;
  final String publicCode;
  final String avatarUrl;
  final String blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      userId: json['userId']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      publicCode: json['publicCode']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      blockedAt: json['blockedAt']?.toString() ?? '',
    );
  }
}
