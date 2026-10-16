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
  bool get isLegacyAggregate =>
      sourceKey == 'doujin-events' || sourceKey == 'doujin-events-daily';

  String get sourceGroup =>
      sourceKey == 'doujin-source' || sourceKey == 'doujin-events-edge'
      ? 'doujin'
      : isLegacyAggregate
      ? 'legacy'
      : sourceKey;

  String get sourceName => switch (sourceKey) {
    'doujin-source' => '同人誌中心',
    'doujin-events-edge' => '同人誌中心（本機匯入）',
    'cosmos-source' => 'COSMOS',
    'acosta-source' => 'acosta!',
    'doujin-events' || 'doujin-events-daily' => '舊版混合來源',
    _ => sourceKey.isEmpty ? '資料同步' : sourceKey,
  };

  String get resultLabel => isLegacyAggregate
      ? '無法判定各來源'
      : isSuccess
      ? '成功 · 匯入 $importedCount 筆'
      : switch (errorCode) {
          'doujin_snapshot_count_drop' => '清單異常縮水，既有活動已保留',
          'doujin_snapshot_identity_conflict' => '活動身份衝突，需確認誤合併資料',
          'doujin_snapshot_count_mismatch' ||
          'doujin_snapshot_truncated' ||
          'doujin_snapshot_invalid_json' ||
          'doujin_snapshot_invalid_event' => '來源清單不完整，未匯入',
          _ => '失敗 · $errorCode',
        };

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
