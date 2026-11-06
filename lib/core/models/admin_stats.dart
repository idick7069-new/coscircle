class AdminStats {
  const AdminStats({
    required this.users,
    required this.suspendedUsers,
    required this.events,
    required this.approvedEvents,
    required this.bookings,
    required this.sharedLocations,
    required this.circles,
    required this.eventSubmissions,
    this.uploadCleanup = 0,
    this.legacyUploadReview = 0,
  });

  final int users;
  final int suspendedUsers;
  final int events;
  final int approvedEvents;
  final int bookings;
  final int sharedLocations;
  final int circles;
  final int eventSubmissions;
  final int uploadCleanup;
  final int legacyUploadReview;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      users: _asInt(json['users']),
      suspendedUsers: _asInt(json['suspendedUsers']),
      events: _asInt(json['events']),
      approvedEvents: _asInt(json['approvedEvents']),
      bookings: _asInt(json['bookings']),
      sharedLocations: _asInt(json['sharedLocations']),
      circles: _asInt(json['circles']),
      eventSubmissions: _asInt(json['eventSubmissions']),
      uploadCleanup: _asInt(json['uploadCleanup']),
      legacyUploadReview: _asInt(json['legacyUploadReview']),
    );
  }
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}
