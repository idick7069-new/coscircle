class EventSubmission {
  const EventSubmission({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.venue,
    required this.description,
    required this.reviewStatus,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String venue;
  final String description;
  final String reviewStatus;
  final DateTime createdAt;

  factory EventSubmission.fromJson(Map<String, dynamic> json) {
    return EventSubmission(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      startDate: _parseDateOnly(json['startDate'].toString()),
      endDate: _parseDateOnly(json['endDate'].toString()),
      venue: json['venue']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      reviewStatus: json['reviewStatus']?.toString() ?? 'pending',
      createdAt: DateTime.parse(json['createdAt'].toString()),
    );
  }
}

DateTime _parseDateOnly(String value) {
  final date = value.split('T').first;
  final parts = date.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
