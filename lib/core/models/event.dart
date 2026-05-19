enum EventStatus { ended, active, upcoming }

class CosEvent {
  const CosEvent({
    required this.id,
    required this.name,
    required this.category,
    required this.startDate,
    required this.endDate,
    required this.venue,
    required this.fee,
    required this.organizer,
    required this.description,
    this.imageUrl = '',
    this.sourceType = 1,
    this.sourceName = '同人誌中心',
    this.sourceUrl = '',
    this.isJoined = false,
    this.hasFollowedParticipants = false,
    this.hasCircleMembers = false,
  });

  final String id;
  final String name;
  final String category;
  final DateTime startDate;
  final DateTime endDate;
  final String venue;
  final String fee;
  final String organizer;
  final String description;
  final String imageUrl;
  final int sourceType;
  final String sourceName;
  final String sourceUrl;
  final bool isJoined;
  final bool hasFollowedParticipants;
  final bool hasCircleMembers;

  factory CosEvent.fromJson(Map<String, dynamic> json) {
    final startDate = _parseDateOnly(json['startDate'].toString());
    final endDate = _parseDateOnly(json['endDate'].toString());
    final sourceType =
        int.tryParse((json['sourceType'] ?? json['type'] ?? '').toString()) ??
        1;
    return CosEvent(
      id: json['id'].toString(),
      name: json['name'].toString(),
      category: json['category'].toString(),
      startDate: startDate,
      endDate: endDate,
      venue: json['venue']?.toString() ?? '',
      fee: json['fee']?.toString() ?? '',
      organizer: json['organizer']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      sourceType: sourceType,
      sourceName: json['sourceName']?.toString() ?? _sourceNameFor(sourceType),
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      isJoined: json['isJoined'] == true || json['isJoined'] == 1,
      hasFollowedParticipants:
          json['hasFollowedParticipants'] == true ||
          json['hasFollowedParticipants'] == 1,
      hasCircleMembers:
          json['hasCircleMembers'] == true || json['hasCircleMembers'] == 1,
    );
  }

  EventStatus status(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (today.isAfter(end)) return EventStatus.ended;
    if (!today.isBefore(start) && !today.isAfter(end)) {
      return EventStatus.active;
    }
    return EventStatus.upcoming;
  }

  CosEvent copyWith({bool? isJoined}) {
    return CosEvent(
      id: id,
      name: name,
      category: category,
      startDate: startDate,
      endDate: endDate,
      venue: venue,
      fee: fee,
      organizer: organizer,
      description: description,
      imageUrl: imageUrl,
      sourceType: sourceType,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      isJoined: isJoined ?? this.isJoined,
      hasFollowedParticipants: hasFollowedParticipants,
      hasCircleMembers: hasCircleMembers,
    );
  }
}

String _sourceNameFor(int type) {
  return switch (type) {
    1 => '同人誌中心',
    2 => '投稿活動',
    _ => '其他來源',
  };
}

DateTime _parseDateOnly(String value) {
  final date = value.split('T').first;
  final parts = date.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
