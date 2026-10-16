import 'admin_sync_run.dart';

class AdminSyncJob {
  const AdminSyncJob({
    required this.id,
    required this.status,
    this.sources = const [],
    this.errorCode = '',
  });
  final String id;
  final String status;
  final List<AdminSyncRun> sources;
  final String errorCode;
  bool get isRunning => status == 'running';

  factory AdminSyncJob.fromJson(Map<String, dynamic> json) => AdminSyncJob(
    id: json['id'].toString(),
    status: json['status'].toString(),
    errorCode: json['errorCode']?.toString() ?? '',
    sources: (json['sources'] as List? ?? [])
        .map(
          (row) => AdminSyncRun.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(),
  );
}
