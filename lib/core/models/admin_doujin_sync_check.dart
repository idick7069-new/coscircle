import 'admin_sync_run.dart';

class AdminDoujinSyncCheck {
  const AdminDoujinSyncCheck({
    required this.sourceUrl,
    required this.sourceAvailable,
    required this.sourceCount,
    required this.databaseCount,
    required this.databaseCurrentOrFutureCount,
    required this.databaseEndedCount,
    required this.matchedCount,
    required this.isCountMatched,
    required this.isFullyMatched,
    required this.missingInDatabase,
    required this.extraInDatabase,
    required this.recentRuns,
    this.sourceError,
  });

  final String sourceUrl;
  final bool sourceAvailable;
  final int? sourceCount;
  final int databaseCount;
  final int databaseCurrentOrFutureCount;
  final int databaseEndedCount;
  final int? matchedCount;
  final bool isCountMatched;
  final bool isFullyMatched;
  final List<AdminDoujinCheckEvent> missingInDatabase;
  final List<AdminDoujinCheckEvent> extraInDatabase;
  final List<AdminSyncRun> recentRuns;
  final AdminDoujinSourceError? sourceError;

  factory AdminDoujinSyncCheck.fromJson(Map<String, dynamic> json) {
    return AdminDoujinSyncCheck(
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      sourceAvailable: json['sourceAvailable'] == true,
      sourceCount: _nullableInt(json['sourceCount']),
      databaseCount: _asInt(json['databaseCount']),
      databaseCurrentOrFutureCount: _asInt(
        json['databaseCurrentOrFutureCount'],
      ),
      databaseEndedCount: _asInt(json['databaseEndedCount']),
      matchedCount: _nullableInt(json['matchedCount']),
      isCountMatched: json['isCountMatched'] == true,
      isFullyMatched: json['isFullyMatched'] == true,
      missingInDatabase: _eventList(json['missingInDatabase']),
      extraInDatabase: _eventList(json['extraInDatabase']),
      recentRuns: ((json['recentRuns'] as List<dynamic>?) ?? const [])
          .map((row) => AdminSyncRun.fromJson(row as Map<String, dynamic>))
          .toList(),
      sourceError: json['sourceError'] is Map<String, dynamic>
          ? AdminDoujinSourceError.fromJson(
              json['sourceError'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class AdminDoujinCheckEvent {
  const AdminDoujinCheckEvent({
    required this.sourceKey,
    required this.category,
    required this.name,
    required this.sourceUrl,
    required this.startDate,
    required this.endDate,
    required this.venue,
    required this.status,
    required this.isEnded,
  });

  final String sourceKey;
  final String category;
  final String name;
  final String sourceUrl;
  final String startDate;
  final String endDate;
  final String venue;
  final String status;
  final bool isEnded;

  factory AdminDoujinCheckEvent.fromJson(Map<String, dynamic> json) {
    return AdminDoujinCheckEvent(
      sourceKey: json['sourceKey']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      venue: json['venue']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      isEnded: json['isEnded'] == true || json['isEnded'] == 1,
    );
  }
}

class AdminDoujinSourceError {
  const AdminDoujinSourceError({required this.code, required this.message});

  final String code;
  final String message;

  factory AdminDoujinSourceError.fromJson(Map<String, dynamic> json) {
    return AdminDoujinSourceError(
      code: json['code']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

List<AdminDoujinCheckEvent> _eventList(Object? value) {
  return ((value as List<dynamic>?) ?? const [])
      .map((row) => AdminDoujinCheckEvent.fromJson(row as Map<String, dynamic>))
      .toList();
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}
