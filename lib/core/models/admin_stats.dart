class AdminStats {
  const AdminStats({
    required this.users,
    required this.events,
    required this.approvedEvents,
    required this.bookings,
    required this.sharedLocations,
    required this.circles,
    required this.eventSubmissions,
  });

  final int users;
  final int events;
  final int approvedEvents;
  final int bookings;
  final int sharedLocations;
  final int circles;
  final int eventSubmissions;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      users: _asInt(json['users']),
      events: _asInt(json['events']),
      approvedEvents: _asInt(json['approvedEvents']),
      bookings: _asInt(json['bookings']),
      sharedLocations: _asInt(json['sharedLocations']),
      circles: _asInt(json['circles']),
      eventSubmissions: _asInt(json['eventSubmissions']),
    );
  }
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}
