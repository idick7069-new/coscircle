import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/report_repository.dart';
import 'package:coscircle/features/admin/presentation/report_management_page.dart';
import 'package:coscircle/features/safety/presentation/report_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AdminContentReport reportFixture({
  ReportTargetType type = ReportTargetType.user,
}) => AdminContentReport(
  id: '7',
  targetType: type,
  reason: ReportReason.harassment,
  status: ReportStatus.pending,
  version: 4,
  reporterUserId: '1',
  targetUserId: '2',
  eventId: type == ReportTargetType.booking ? '10' : null,
  dayIndex: type == ReportTargetType.booking ? 2 : null,
  details: 'reported context',
  snapshot: const {'nickname': 'target'},
  reviews: const [],
);

class FakeReportRepository extends ReportRepository {
  FakeReportRepository()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final submissions = <Map<String, Object?>>[];
  final reviews = <Map<String, Object?>>[];
  final filters = <ReportStatus>[];
  List<AdminContentReport> items = [reportFixture()];
  Object? submitError;
  Object? reviewError;
  Completer<void>? submission;

  @override
  Future<void> submit({
    required ReportTarget target,
    required ReportReason reason,
    String details = '',
  }) async {
    submissions.add({
      ...target.toJson(),
      'reason': reason.value,
      'details': details,
    });
    if (submitError != null) throw submitError!;
    await submission?.future;
  }

  @override
  Future<ReportPage> fetchReports({
    required ReportStatus status,
    String? beforeId,
  }) async {
    filters.add(status);
    return ReportPage(
      items: items.where((item) => item.status == status).toList(),
    );
  }

  @override
  Future<void> review({
    required AdminContentReport report,
    required ReportStatus status,
    required ReportAction action,
    String note = '',
  }) async {
    reviews.add({
      'id': report.id,
      'expectedVersion': report.version,
      'status': status.value,
      'action': action.value,
      'note': note,
    });
    if (reviewError != null) throw reviewError!;
    items = [];
  }
}

class RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.method == 'GET'
        ? {
            'items': [
              {
                'id': '7',
                'targetType': 'booking',
                'targetUserId': '2',
                'reason': 'spam',
                'status': 'pending',
                'version': 4,
                'snapshot': {
                  'outfitImageUrl': 'https://images.invalid/photo.jpg',
                },
                'reviews': [],
              },
            ],
            'nextBeforeId': '7',
          }
        : {'id': '7', 'status': 'pending'};
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioException staleReview() => DioException(
  requestOptions: RequestOptions(path: '/admin/reports/7/review'),
  response: Response(
    requestOptions: RequestOptions(path: '/admin/reports/7/review'),
    statusCode: 409,
    data: {'error': 'stale_report'},
  ),
);

Future<void> openPage(
  WidgetTester tester,
  FakeReportRepository repository,
  Widget page,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [reportRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openReport(
  WidgetTester tester,
  FakeReportRepository repository, {
  bool incomplete = false,
}) async {
  await openPage(
    tester,
    repository,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showReportSheet(
              context,
              targetType: 'booking',
              targetUserId: '2',
              eventId: incomplete ? null : 10,
              dayIndex: 2,
              targetLabel: 'target',
            ),
            child: const Text('檢舉'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('檢舉'));
  await tester.pumpAndSettle();
}

Future<void> chooseReason(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<ReportReason>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('垃圾訊息或廣告').last);
  await tester.pumpAndSettle();
}

Future<void> openReview(
  WidgetTester tester,
  FakeReportRepository repository,
) async {
  await openPage(tester, repository, const ReportManagementPage());
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('審核'));
  await tester.tap(find.text('審核'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'repository sends only canonical target data and carries queue cursor and review version',
    () async {
      final adapter = RecordingAdapter();
      final client = ApiClient(
        baseUrl: 'https://example.invalid/api',
        adapter: adapter,
      )..setAuthToken('fixture');
      final repository = ReportRepository(apiClient: client);
      await repository.submit(
        target: const ReportTarget.booking(
          userId: '2',
          eventId: 10,
          dayIndex: 2,
          label: 'local-only',
        ),
        reason: ReportReason.spam,
        details: ' context ',
      );
      expect(adapter.requests[0].path, '/reports');
      expect(adapter.requests[0].data, {
        'targetType': 'booking',
        'targetUserId': '2',
        'eventId': 10,
        'dayIndex': 2,
        'reason': 'spam',
        'details': 'context',
      });
      final page = await repository.fetchReports(
        status: ReportStatus.pending,
        beforeId: '9',
      );
      expect(adapter.requests[1].queryParameters, {
        'status': 'pending',
        'beforeId': '9',
      });
      expect(page.nextBeforeId, '7');
      expect(page.items.single.evidencePhotoUrls, [
        'https://images.invalid/photo.jpg',
      ]);
      await repository.review(
        report: page.items.single,
        status: ReportStatus.dismissed,
        action: ReportAction.none,
        note: ' reviewed ',
      );
      expect(adapter.requests[2].path, '/admin/reports/7/review');
      expect(adapter.requests[2].data, {
        'status': 'dismissed',
        'action': 'none',
        'note': 'reviewed',
        'expectedVersion': 4,
      });
      expect(const ReportTarget.circle(circleId: '20').toJson(), {
        'targetType': 'circle',
        'circleId': '20',
      });
      expect(const ReportTarget.user(userId: '2').toJson(), {
        'targetType': 'user',
        'targetUserId': '2',
      });
    },
  );

  test(
    'evidence previews accept bounded HTTPS URLs without credentials and at most three other photos',
    () {
      for (final value in [
        'http://images.invalid/photo',
        'https://user@images.invalid/photo',
        'https://user:password@images.invalid/photo',
        'data:image/png,secret',
        'javascript:alert(1)',
        'https://',
        'https://images.invalid/${'x' * 2048}',
      ]) {
        expect(isSafeReportPhotoUrl(value), isFalse, reason: value);
      }
      final report = AdminContentReport.fromJson({
        'id': '7',
        'targetType': 'user',
        'reason': 'privacy',
        'status': 'pending',
        'version': 1,
        'snapshot': {
          'avatarUrl': 'http://images.invalid/avatar',
          'otherPhotoUrls': [
            'https://images.invalid/one',
            'https://images.invalid/two',
            'https://images.invalid/three',
            'https://images.invalid/four',
          ],
        },
      });
      expect(report.evidencePhotoUrls, [
        'https://images.invalid/one',
        'https://images.invalid/two',
        'https://images.invalid/three',
      ]);
      expect(report.availableActions, [ReportAction.none]);
      expect(reportErrorMessage(staleReview()), '檢舉狀態已變更，請重新整理後再審核');
    },
  );

  testWidgets(
    'incomplete integration parameters show an error without sending a report',
    (tester) async {
      final repository = FakeReportRepository();
      await openReport(tester, repository, incomplete: true);
      expect(find.text('檢舉對象資料不完整，請重新整理'), findsOneWidget);
      expect(repository.submissions, isEmpty);
    },
  );

  testWidgets(
    'report requires a reason, preserves target day, and disables duplicate submission',
    (tester) async {
      final repository = FakeReportRepository()..submission = Completer<void>();
      await openReport(tester, repository);
      await tester.ensureVisible(find.text('送出檢舉'));
      await tester.tap(find.text('送出檢舉'));
      await tester.pumpAndSettle();
      expect(find.text('請選擇檢舉原因'), findsOneWidget);
      expect(repository.submissions, isEmpty);
      await chooseReason(tester);
      await tester.enterText(find.byType(TextFormField), 'specific concern');
      await tester.ensureVisible(find.text('送出檢舉'));
      await tester.tap(find.text('送出檢舉'));
      await tester.pump();
      expect(repository.submissions.single, {
        'targetType': 'booking',
        'targetUserId': '2',
        'eventId': 10,
        'dayIndex': 2,
        'reason': 'spam',
        'details': 'specific concern',
      });
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '關閉',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('送出中'));
      await tester.pump();
      expect(repository.submissions.length, 1);
      repository.submission!.complete();
      await tester.pumpAndSettle();
      expect(find.text('檢舉已送出，將由管理員審核'), findsOneWidget);
    },
  );

  testWidgets('failed submission retains explanation and remains retryable', (
    tester,
  ) async {
    final repository = FakeReportRepository()
      ..submitError = Exception('network interrupted');
    await openReport(tester, repository);
    await chooseReason(tester);
    await tester.enterText(find.byType(TextFormField), 'retained context');
    await tester.ensureVisible(find.text('送出檢舉'));
    await tester.tap(find.text('送出檢舉'));
    await tester.pumpAndSettle();
    expect(find.text('network interrupted'), findsOneWidget);
    expect(find.text('retained context'), findsOneWidget);
    expect(find.text('檢舉已送出，將由管理員審核'), findsNothing);
    repository.submitError = null;
    await tester.ensureVisible(find.text('送出檢舉'));
    await tester.tap(find.text('送出檢舉'));
    await tester.pumpAndSettle();
    expect(repository.submissions.length, 2);
  });

  testWidgets(
    'admin filtering loads the selected status and displays its empty state',
    (tester) async {
      final repository = FakeReportRepository();
      await openPage(tester, repository, const ReportManagementPage());
      expect(find.textContaining('#7'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<ReportStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('審核中').last);
      await tester.pumpAndSettle();
      expect(repository.filters, [
        ReportStatus.pending,
        ReportStatus.reviewing,
      ]);
      expect(find.text('目前沒有這個狀態的檢舉'), findsOneWidget);
    },
  );

  testWidgets(
    'admin review submits displayed version and refreshes the queue',
    (tester) async {
      final repository = FakeReportRepository();
      await openReview(tester, repository);
      await tester.ensureVisible(find.text('儲存審核'));
      await tester.tap(find.text('儲存審核'));
      await tester.pumpAndSettle();
      expect(repository.reviews.single, {
        'id': '7',
        'expectedVersion': 4,
        'status': 'reviewing',
        'action': 'none',
        'note': '',
      });
      expect(find.text('目前沒有這個狀態的檢舉'), findsOneWidget);
    },
  );

  testWidgets(
    'stale review requires loading the new version before another submit',
    (tester) async {
      final repository = FakeReportRepository()..reviewError = staleReview();
      await openReview(tester, repository);
      await tester.ensureVisible(find.text('儲存審核'));
      await tester.tap(find.text('儲存審核'));
      await tester.pumpAndSettle();
      expect(find.text('檢舉狀態已變更，請重新整理後再審核'), findsOneWidget);
      expect(find.text('儲存審核'), findsNothing);
      await tester.ensureVisible(find.text('重新載入'));
      await tester.tap(find.text('重新載入'));
      await tester.pumpAndSettle();
      expect(repository.reviews.length, 1);
      expect(repository.filters.length, 2);
    },
  );

  testWidgets(
    'destructive review requires a reason and a second confirmation',
    (tester) async {
      final repository = FakeReportRepository()
        ..items = [reportFixture(type: ReportTargetType.booking)];
      await openReview(tester, repository);
      await tester.tap(find.byType(DropdownButtonFormField<ReportStatus>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('已處理').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<ReportAction>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除出席資訊').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('儲存審核'));
      await tester.tap(find.text('儲存審核'));
      await tester.pumpAndSettle();
      expect(find.text('請填寫處置原因'), findsOneWidget);
      expect(repository.reviews, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'confirmed spam');
      await tester.ensureVisible(find.text('儲存審核'));
      await tester.tap(find.text('儲存審核'));
      await tester.pumpAndSettle();
      expect(repository.reviews, isEmpty);
      await tester.tap(find.text('確認處置'));
      await tester.pumpAndSettle();
      expect(repository.reviews.single['action'], 'remove_booking');
      expect(repository.reviews.single['note'], 'confirmed spam');
    },
  );
}
