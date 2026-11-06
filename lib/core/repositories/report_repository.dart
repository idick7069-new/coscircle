import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../utils/error_message.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(apiClient: ref.watch(apiClientProvider));
});

enum ReportTargetType {
  user('user', '使用者'),
  booking('booking', '出席資訊'),
  circle('circle', '小圈圈');

  const ReportTargetType(this.value, this.label);
  final String value;
  final String label;
}

class ReportTarget {
  const ReportTarget._({
    required this.type,
    this.targetUserId,
    this.eventId,
    this.dayIndex,
    this.circleId,
    this.label,
  });

  const ReportTarget.user({required String userId, String? label})
    : this._(type: ReportTargetType.user, targetUserId: userId, label: label);

  const ReportTarget.booking({
    required String userId,
    required int eventId,
    required int dayIndex,
    String? label,
  }) : this._(
         type: ReportTargetType.booking,
         targetUserId: userId,
         eventId: eventId,
         dayIndex: dayIndex,
         label: label,
       );

  const ReportTarget.circle({required String circleId, String? label})
    : this._(type: ReportTargetType.circle, circleId: circleId, label: label);

  final ReportTargetType type;
  final String? targetUserId;
  final int? eventId;
  final int? dayIndex;
  final String? circleId;
  final String? label;

  Map<String, dynamic> toJson() => {
    'targetType': type.value,
    if (targetUserId != null) 'targetUserId': targetUserId,
    if (eventId != null) 'eventId': eventId,
    if (dayIndex != null) 'dayIndex': dayIndex,
    if (circleId != null) 'circleId': circleId,
  };
}

enum ReportReason {
  spam('spam', '垃圾訊息或廣告'),
  harassment('harassment', '騷擾或霸凌'),
  sexualContent('sexual_content', '色情或不當裸露'),
  hate('hate', '仇恨或歧視'),
  impersonation('impersonation', '冒用身分'),
  privacy('privacy', '侵犯隱私'),
  other('other', '其他');

  const ReportReason(this.value, this.label);
  final String value;
  final String label;
}

enum ReportStatus {
  pending('pending', '待審核'),
  reviewing('reviewing', '審核中'),
  resolved('resolved', '已處理'),
  dismissed('dismissed', '不予處理');

  const ReportStatus(this.value, this.label);
  final String value;
  final String label;
  bool get isClosed => this == resolved || this == dismissed;
}

enum ReportAction {
  none('none', '不變更內容或帳號'),
  suspendUser('suspend_user', '停權使用者'),
  removeBooking('remove_booking', '移除出席資訊'),
  removeCircle('remove_circle', '移除小圈圈');

  const ReportAction(this.value, this.label);
  final String value;
  final String label;
}

class ReportReview {
  const ReportReview({
    required this.status,
    required this.action,
    this.adminUserId,
    this.note,
    this.createdAt,
  });

  final ReportStatus status;
  final ReportAction action;
  final String? adminUserId;
  final String? note;
  final DateTime? createdAt;

  factory ReportReview.fromJson(Map<String, dynamic> json) => ReportReview(
    status: ReportStatus.values.firstWhere(
      (item) => item.value == json['status'],
    ),
    action: ReportAction.values.firstWhere(
      (item) => item.value == json['action'],
    ),
    adminUserId: json['adminUserId']?.toString(),
    note: json['note'] as String?,
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
  );
}

class AdminContentReport {
  const AdminContentReport({
    required this.id,
    required this.targetType,
    required this.reason,
    required this.status,
    required this.version,
    required this.reviews,
    this.reporterUserId,
    this.targetUserId,
    this.eventId,
    this.dayIndex,
    this.circleId,
    this.details,
    this.snapshot,
    this.createdAt,
    this.evidenceExpiresAt,
  });

  final String id;
  final ReportTargetType targetType;
  final ReportReason reason;
  final ReportStatus status;
  final int version;
  final String? reporterUserId;
  final String? targetUserId;
  final String? eventId;
  final int? dayIndex;
  final String? circleId;
  final String? details;
  final Map<String, Object?>? snapshot;
  final DateTime? createdAt;
  final DateTime? evidenceExpiresAt;
  final List<ReportReview> reviews;

  List<String> get evidencePhotoUrls {
    final photos = <Object?>[
      snapshot?['avatarUrl'],
      snapshot?['outfitImageUrl'],
    ];
    final others = snapshot?['otherPhotoUrls'];
    if (others is List) photos.addAll(others.take(3));
    return photos
        .whereType<String>()
        .where(isSafeReportPhotoUrl)
        .toSet()
        .toList();
  }

  List<ReportAction> get availableActions => [
    ReportAction.none,
    if (snapshot != null && !status.isClosed) ...[
      if (targetUserId != null) ReportAction.suspendUser,
      if (targetType == ReportTargetType.booking &&
          targetUserId != null &&
          eventId != null)
        ReportAction.removeBooking,
      if (targetType == ReportTargetType.circle && circleId != null)
        ReportAction.removeCircle,
    ],
  ];

  factory AdminContentReport.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'] as Map?;
    return AdminContentReport(
      id: json['id'].toString(),
      targetType: ReportTargetType.values.firstWhere(
        (item) => item.value == json['targetType'],
      ),
      reason: ReportReason.values.firstWhere(
        (item) => item.value == json['reason'],
      ),
      status: ReportStatus.values.firstWhere(
        (item) => item.value == json['status'],
      ),
      version: (json['version'] as num).toInt(),
      reporterUserId: json['reporterUserId']?.toString(),
      targetUserId: json['targetUserId']?.toString(),
      eventId: json['eventId']?.toString(),
      dayIndex: (json['dayIndex'] as num?)?.toInt(),
      circleId: json['circleId']?.toString(),
      details: json['details'] as String?,
      snapshot: snapshot == null ? null : Map<String, Object?>.from(snapshot),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      evidenceExpiresAt: DateTime.tryParse(
        json['evidenceExpiresAt']?.toString() ?? '',
      ),
      reviews: (json['reviews'] as List? ?? const [])
          .map(
            (row) =>
                ReportReview.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
    );
  }
}

class ReportPage {
  const ReportPage({required this.items, this.nextBeforeId});
  final List<AdminContentReport> items;
  final String? nextBeforeId;
}

class ReportRepository {
  ReportRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<void> submit({
    required ReportTarget target,
    required ReportReason reason,
    String details = '',
  }) async {
    await _apiClient.post(
      '/reports',
      data: {
        ...target.toJson(),
        'reason': reason.value,
        'details': details.trim(),
      },
    );
  }

  Future<ReportPage> fetchReports({
    required ReportStatus status,
    String? beforeId,
  }) async {
    final response = await _apiClient.get(
      '/admin/reports',
      query: {
        'status': status.value,
        if (beforeId != null) 'beforeId': beforeId,
      },
    );
    final json = Map<String, dynamic>.from(response.data as Map);
    return ReportPage(
      items: (json['items'] as List)
          .map(
            (row) => AdminContentReport.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
      nextBeforeId: json['nextBeforeId']?.toString(),
    );
  }

  Future<void> review({
    required AdminContentReport report,
    required ReportStatus status,
    required ReportAction action,
    String note = '',
  }) async {
    await _apiClient.post(
      '/admin/reports/${report.id}/review',
      data: {
        'status': status.value,
        'action': action.value,
        'note': note.trim(),
        'expectedVersion': report.version,
      },
    );
  }
}

String? reportErrorCode(Object error) {
  if (error is DioException && error.response?.data is Map) {
    return (error.response!.data as Map)['error']?.toString();
  }
  return null;
}

bool isSafeReportPhotoUrl(String value) {
  if (value.length > 2048) return false;
  try {
    final uri = Uri.parse(value);
    return uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  } on FormatException {
    return false;
  }
}

String reportErrorMessage(Object error) {
  if (error is DioException && error.response?.data is Map) {
    final code = reportErrorCode(error);
    final message = switch (code) {
      'duplicate_report' => '已收到這個對象的檢舉，請勿重複送出',
      'cannot_report_self' => '無法檢舉自己或自己建立的小圈圈',
      'report_target_unavailable' => '目前無法查看這筆內容，請重新整理',
      'stale_report' => '檢舉狀態已變更，請重新整理後再審核',
      'report_target_changed' => '原內容已變更或移除，請重新確認後結案',
      'report_evidence_unavailable' => '檢舉證據已清除，無法執行內容或帳號操作',
      'protected_admin_account' => '管理員帳號受保護，請使用使用者管理流程處理',
      'review_note_required' => '請填寫處置原因',
      'invalid_details' || 'invalid_note' => '補充內容不可超過 1000 字',
      'invalid_review' ||
      'action_target_mismatch' ||
      'action_requires_resolution' => '請確認審核狀態與處置方式',
      _ => null,
    };
    if (message != null) return message;
  }
  return userFacingError(error);
}
