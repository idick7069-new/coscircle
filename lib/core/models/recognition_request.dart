enum RecognitionStatus {
  pending,
  accepted,
  declined,
  expired,
  cancelled;

  static RecognitionStatus fromValue(String value) {
    return switch (value) {
      'accepted' || 'come' => RecognitionStatus.accepted,
      'declined' || 'busy' => RecognitionStatus.declined,
      'expired' => RecognitionStatus.expired,
      'cancelled' => RecognitionStatus.cancelled,
      _ => RecognitionStatus.pending,
    };
  }

  String get value {
    return switch (this) {
      RecognitionStatus.pending => 'pending',
      RecognitionStatus.accepted => 'accepted',
      RecognitionStatus.declined => 'declined',
      RecognitionStatus.expired => 'expired',
      RecognitionStatus.cancelled => 'cancelled',
    };
  }
}

class RecognitionRequest {
  const RecognitionRequest({
    required this.id,
    required this.eventId,
    required this.requesterUserId,
    required this.requesterNickname,
    required this.targetUserId,
    required this.targetNickname,
    required this.status,
    required this.createdAt,
    this.responseMessage = '',
    this.respondedAt,
    this.isRequester = false,
    this.isTarget = false,
    this.dayIndex = 1,
    this.expiresAt,
  });

  final String id;
  final String eventId;
  final String requesterUserId;
  final String requesterNickname;
  final String targetUserId;
  final String targetNickname;
  final RecognitionStatus status;
  final String responseMessage;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final bool isRequester;
  final bool isTarget;
  final int dayIndex;
  final DateTime? expiresAt;

  DateTime get effectiveExpiry =>
      expiresAt ?? createdAt.add(const Duration(minutes: 5));

  bool isNoticeAt(DateTime now, int currentDayIndex) {
    if (dayIndex != currentDayIndex) return false;
    final createdDay = createdAt.toUtc().add(const Duration(hours: 8));
    final today = now.toUtc().add(const Duration(hours: 8));
    if (createdDay.year != today.year ||
        createdDay.month != today.month ||
        createdDay.day != today.day) {
      return false;
    }
    if (status == RecognitionStatus.pending) {
      return isTarget && effectiveExpiry.isAfter(now);
    }
    if (!isRequester ||
        (status != RecognitionStatus.accepted &&
            status != RecognitionStatus.declined)) {
      return false;
    }
    final replied = respondedAt;
    return replied != null &&
        !replied.isAfter(now) &&
        replied.add(const Duration(minutes: 15)).isAfter(now);
  }

  factory RecognitionRequest.fromJson(Map<String, dynamic> json) {
    final respondedAtText = json['respondedAt']?.toString() ?? '';
    return RecognitionRequest(
      id: json['id'].toString(),
      eventId: json['eventId'].toString(),
      requesterUserId: json['requesterUserId'].toString(),
      requesterNickname: json['requesterNickname']?.toString() ?? '',
      targetUserId: json['targetUserId'].toString(),
      targetNickname: json['targetNickname']?.toString() ?? '',
      status: RecognitionStatus.fromValue(json['status']?.toString() ?? ''),
      responseMessage: json['responseMessage']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt'].toString()).toLocal(),
      respondedAt: respondedAtText.isEmpty
          ? null
          : DateTime.tryParse(respondedAtText)?.toLocal(),
      dayIndex: int.tryParse(json['dayIndex']?.toString() ?? '') ?? 1,
      expiresAt: DateTime.tryParse(
        json['expiresAt']?.toString() ?? '',
      )?.toLocal(),
      isRequester: json['isRequester'] == true || json['isRequester'] == 1,
      isTarget: json['isTarget'] == true || json['isTarget'] == 1,
    );
  }
}
