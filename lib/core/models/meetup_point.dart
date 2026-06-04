class MeetupPoint {
  const MeetupPoint({
    required this.id,
    required this.eventId,
    required this.circleId,
    required this.circleName,
    required this.creatorUserId,
    required this.creatorNickname,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.meetAt,
    required this.createdAt,
    required this.isMine,
  });

  final String id;
  final String eventId;
  final String circleId;
  final String circleName;
  final String creatorUserId;
  final String creatorNickname;
  final double latitude;
  final double longitude;
  final String description;
  final DateTime meetAt;
  final DateTime createdAt;
  final bool isMine;

  factory MeetupPoint.fromJson(Map<String, dynamic> json) {
    return MeetupPoint(
      id: json['id'].toString(),
      eventId: json['eventId'].toString(),
      circleId: json['circleId'].toString(),
      circleName: json['circleName']?.toString() ?? '',
      creatorUserId: json['creatorUserId'].toString(),
      creatorNickname: json['creatorNickname']?.toString() ?? '',
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      description: json['description']?.toString() ?? '',
      meetAt: DateTime.parse(json['meetAt'].toString()),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      isMine: json['isMine'] == true || json['isMine'] == 1,
    );
  }
}
