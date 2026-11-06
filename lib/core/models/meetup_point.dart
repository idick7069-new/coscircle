DateTime taipeiDateTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));

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

  bool isActiveAt(DateTime now) {
    final date = taipeiDateTime(meetAt);
    final today = taipeiDateTime(now);
    return date.year == today.year &&
        date.month == today.month &&
        date.day == today.day &&
        meetAt.isAfter(now.subtract(const Duration(minutes: 10)));
  }

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
      meetAt: DateTime.parse(json['meetAt'].toString()).toLocal(),
      createdAt: DateTime.parse(json['createdAt'].toString()).toLocal(),
      isMine: json['isMine'] == true || json['isMine'] == 1,
    );
  }
}

// Only successful fetches advance the snapshot; null means loading or failure.
class MeetupSnapshot {
  Map<String, MeetupPoint>? _known;

  List<MeetupPoint> get items => _known?.values.toList() ?? const [];

  List<String> update(List<MeetupPoint>? successfulItems, DateTime now) {
    if (successfulItems == null) return const [];
    final previous = _known;
    final current = {for (final item in successfulItems) item.id: item};
    _known = current;
    if (previous == null) return const [];
    final messages = <String>[];
    for (final item in successfulItems) {
      final old = previous[item.id];
      // Creation is delivered exclusively by meetup_created push.
      if (old == null || item.isMine || !item.isActiveAt(now)) continue;
      if (old.latitude != item.latitude ||
          old.longitude != item.longitude ||
          old.description != item.description ||
          old.meetAt != item.meetAt ||
          old.circleId != item.circleId) {
        messages.add('${item.circleName} 更改了集合位置');
      }
    }
    for (final old in previous.values) {
      if (!old.isMine && old.isActiveAt(now) && !current.containsKey(old.id)) {
        messages.add('${old.circleName} 取消了集合');
      }
    }
    return messages;
  }
}
