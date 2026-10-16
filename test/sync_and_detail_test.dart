import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/admin_sync_job.dart';
import 'package:coscircle/core/models/booking.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/models/shared_location.dart';
import 'package:coscircle/core/providers/admin_sync_provider.dart';
import 'package:coscircle/core/repositories/admin_repository.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/location_repository.dart';
import 'package:coscircle/features/events/presentation/event_booking_sheet.dart';
import 'package:coscircle/features/events/presentation/event_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class DetailEvents extends InMemoryEventRepository {
  DetailEvents({this.broken = false});
  final bool broken;
  final List<EventBooking> writes = [];
  CosEvent get event {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return CosEvent(
      id: 'detail',
      name: 'QA',
      category: 'ONLY',
      startDate: today.subtract(const Duration(days: 1)),
      endDate: today.add(const Duration(days: 1)),
      venue: 'Expo',
      detailedAddress: '',
      fee: '',
      organizer: '',
      description: '',
      isJoined: true,
      joinedDayIndexes: const [2],
    );
  }

  @override
  Future<List<CosEvent>> fetchEvents() async => [event];
  @override
  Future<List<EventParticipant>> fetchParticipants(String eventId) async {
    if (broken) throw Exception('participant unavailable');
    return [
      const EventParticipant(
        userId: 'me',
        nickname: 'QA',
        role: 'photographer',
        dayIndex: 2,
        isMe: true,
      ),
    ];
  }

  @override
  Future<void> upsertBooking(EventBooking booking) async {
    writes.add(booking);
  }
}

class BrowsingEvents extends DetailEvents {
  BrowsingEvents({this.empty = false});
  final bool empty;

  @override
  CosEvent get event =>
      super.event.copyWith(isJoined: false, joinedDayIndexes: const []);

  @override
  Future<List<EventParticipant>> fetchParticipants(String eventId) async =>
      empty
      ? []
      : [
          const EventParticipant(
            userId: 'peer',
            nickname: '公開預定同好',
            role: 'coser',
            dayIndex: 2,
            workName: '測試作品',
            characterName: '測試角色',
            message: '下午在場',
          ),
        ];
}

class SyncRepository extends AdminRepository {
  SyncRepository()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  int starts = 0;
  AdminSyncJob? job;
  @override
  Future<AdminSyncJob?> fetchSyncJob(String id) async => job;
  @override
  Future<AdminSyncJob> syncDoujinEvents() async {
    starts++;
    return job = const AdminSyncJob(id: 'job', status: 'running');
  }
}

class CoordinateClient extends ApiClient {
  CoordinateClient() : super(baseUrl: 'https://example.invalid/api');
  String? path;
  Object? payload;

  @override
  Future<Response<dynamic>> put(String path, {Object? data}) async {
    this.path = path;
    payload = data;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 204,
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  for (final empty in [false, true]) {
    testWidgets(
      'browsing without attendance shows ${empty ? 'empty state' : 'public booking'}',
      (tester) async {
        final events = BrowsingEvents(empty: empty);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [eventRepositoryProvider.overrideWithValue(events)],
            child: MaterialApp(home: const EventDetailPage(eventId: 'detail')),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.text(empty ? '目前沒有可顯示的預定。' : '公開預定同好');
        await tester.scrollUntilVisible(target, 250);
        await tester.pumpAndSettle();
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target, findsOneWidget);
        expect(find.text('產生預訂分享圖'), findsNothing);
        if (!empty) {
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(find.text('下午在場'), findsOneWidget);
          expect(find.textContaining('測試角色'), findsOneWidget);
        }
        expect(events.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'detail locks each date, disables the past, and edits D2 using the shared form',
    (tester) async {
      final events = DetailEvents();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [eventRepositoryProvider.overrideWithValue(events)],
          child: MaterialApp(
            locale: const Locale('zh', 'TW'),
            supportedLocales: const [Locale('zh', 'TW')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const EventDetailPage(eventId: 'detail'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-booking-1')),
        250,
      );
      final yesterday = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('detail-booking-1')),
      );
      expect(yesterday.onPressed, isNull);
      final edit = find.byKey(const ValueKey('detail-booking-2'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final sheet = tester.widget<BookingSheet>(find.byType(BookingSheet));
      expect(sheet.initialDayIndex, 2);
      expect(sheet.initialParticipant?.role, 'photographer');
      expect(events.writes, isEmpty);
      expect(tester.takeException(), isNull);
      final formScrollable = find
          .descendant(
            of: find.byType(BookingSheet),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('儲存出席'),
        300,
        scrollable: formScrollable,
      );
      await tester.tap(find.text('儲存出席'));
      await tester.pumpAndSettle();
      expect(events.writes.single.dayIndex, 2);
    },
  );

  testWidgets('failed participant loading cannot open a blank edit form', (
    tester,
  ) async {
    final events = DetailEvents(broken: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eventRepositoryProvider.overrideWithValue(events)],
        child: MaterialApp(
          locale: const Locale('zh', 'TW'),
          supportedLocales: const [Locale('zh', 'TW')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const EventDetailPage(eventId: 'detail'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('detail-booking-2')),
      250,
    );
    await tester.tap(find.byKey(const ValueKey('detail-booking-2')));
    await tester.pumpAndSettle();
    expect(find.byType(BookingSheet), findsNothing);
    expect(events.writes, isEmpty);
  });

  testWidgets(
    'sync controller deduplicates clicks and polls completion without another POST',
    (tester) async {
      final repository = SyncRepository();
      final container = ProviderContainer(
        overrides: [adminRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = container.listen(adminSyncJobProvider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await container.read(adminSyncJobProvider.future);
      await container.read(adminSyncJobProvider.notifier).start();
      await container.read(adminSyncJobProvider.notifier).start();
      expect(repository.starts, 1);
      repository.job = const AdminSyncJob(id: 'job', status: 'success');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(container.read(adminSyncJobProvider).value?.status, 'success');
      expect(repository.starts, 1);
    },
  );

  testWidgets('opening the page restores polling for an existing server job', (
    tester,
  ) async {
    final repository = SyncRepository()
      ..job = const AdminSyncJob(id: 'existing', status: 'running');
    final container = ProviderContainer(
      overrides: [adminRepositoryProvider.overrideWithValue(repository)],
    );
    final subscription = container.listen(adminSyncJobProvider, (_, _) {});
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    expect((await container.read(adminSyncJobProvider.future))?.id, 'existing');
    repository.job = const AdminSyncJob(id: 'existing', status: 'partial');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(container.read(adminSyncJobProvider).value?.status, 'partial');
    expect(repository.starts, 0);
  });

  test(
    'updating coordinates does not resend visibility or extend sharing expiry',
    () async {
      final client = CoordinateClient();
      await ApiLocationRepository(apiClient: client).updateSharedLocation(
        eventId: 'detail',
        dayIndex: 2,
        latitude: 25,
        longitude: 121,
      );
      expect(client.path, '/events/detail/location/coordinates');
      expect(client.payload, {
        'dayIndex': 2,
        'latitude': 25.0,
        'longitude': 121.0,
      });
    },
  );

  test(
    'location epoch fields represent the right instant without device timezone ambiguity',
    () {
      final location = SharedLocation.fromJson({
        'userId': 1,
        'latitude': 25,
        'longitude': 121,
        'sharedAt': '2026-10-06T12:00:00',
        'sharedAtEpoch': 1791259200,
        'expiresAtEpoch': 1791261000,
      });
      expect(location.sharedAt.millisecondsSinceEpoch, 1791259200000);
      expect(location.expiresAt!.difference(location.sharedAt).inMinutes, 30);
    },
  );
}
