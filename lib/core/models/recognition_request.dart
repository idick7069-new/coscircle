enum RecognitionStatus {
  pending,
  come,
  busy;

  static RecognitionStatus fromValue(String value) {
    return switch (value) {
      'come' => RecognitionStatus.come,
      'busy' => RecognitionStatus.busy,
      _ => RecognitionStatus.pending,
    };
  }

  String get value {
    return switch (this) {
      RecognitionStatus.pending => 'pending',
      RecognitionStatus.come => 'come',
      RecognitionStatus.busy => 'busy',
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
      createdAt: DateTime.parse(json['createdAt'].toString()),
      respondedAt: respondedAtText.isEmpty
          ? null
          : DateTime.tryParse(respondedAtText),
      isRequester: json['isRequester'] == true || json['isRequester'] == 1,
      isTarget: json['isTarget'] == true || json['isTarget'] == 1,
    );
  }
}
