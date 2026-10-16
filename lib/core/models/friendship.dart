class Friendship {
  const Friendship({
    required this.id,
    required this.userId,
    required this.publicCode,
    required this.nickname,
    required this.status,
    required this.introduction,
    required this.requesterId,
    this.avatarUrl = '',
    this.eventId = '',
    this.eventName = '',
    this.eventDate = '',
    this.dayIndex,
  });

  final String id;
  final String userId;
  final String publicCode;
  final String nickname;
  final String status;
  final String introduction;
  final String requesterId;
  final String avatarUrl;
  final String eventId;
  final String eventName;
  final String eventDate;
  final int? dayIndex;

  bool get isIncoming => status == 'incoming';
  bool get isAccepted => status == 'accepted';
  bool get introductionIsMine => requesterId != userId;
  String get eventLabel => eventName.isEmpty
      ? '未指定場次'
      : '$eventName${dayIndex == null ? '' : ' · D$dayIndex'} · $eventDate';

  factory Friendship.fromJson(Map<String, dynamic> json) => Friendship(
    id: json['id'].toString(),
    userId: json['userId'].toString(),
    publicCode: json['publicCode']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? '',
    status: json['status']?.toString() ?? 'pending',
    introduction: json['introduction']?.toString() ?? '',
    requesterId: json['requesterId'].toString(),
    avatarUrl: json['avatarUrl']?.toString() ?? '',
    eventId: json['eventId']?.toString() ?? '',
    eventName: json['eventName']?.toString() ?? '',
    eventDate: json['eventDate']?.toString() ?? '',
    dayIndex: int.tryParse(json['dayIndex']?.toString() ?? ''),
  );
}
