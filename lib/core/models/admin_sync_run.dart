class AdminSyncRun {
  const AdminSyncRun({
    required this.sourceKey,
    required this.sourceUrl,
    required this.status,
    required this.importedCount,
    required this.createdAt,
    this.errorCode = '',
    this.errorMessage = '',
  });

  final String sourceKey;
  final String sourceUrl;
  final String status;
  final int importedCount;
  final String errorCode;
  final String errorMessage;
  final String createdAt;

  bool get isSuccess => status == 'success';

  factory AdminSyncRun.fromJson(Map<String, dynamic> json) {
    return AdminSyncRun(
      sourceKey: json['sourceKey']?.toString() ?? '',
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      importedCount: _asInt(json['importedCount']),
      errorCode: json['errorCode']?.toString() ?? '',
      errorMessage: json['errorMessage']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}
