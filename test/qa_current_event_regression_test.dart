import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/meetup_point.dart';
import 'package:coscircle/core/models/recognition_request.dart';
import 'package:coscircle/core/providers/event_providers.dart';
import 'package:coscircle/core/repositories/location_repository.dart';
import 'package:coscircle/core/services/local_notification_service.dart';
import 'package:coscircle/core/services/push_notification_service.dart';
import 'package:coscircle/features/current_event/presentation/current_event_page.dart';
import 'package:coscircle/features/current_event/presentation/widgets/current_event_overlays.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 10, 28, 5);

MeetupPoint _meetup({
  String id = 'meetup',
  DateTime? at,
  String description = '北門',
  bool mine = false,
}) => MeetupPoint(
  id: id,
  eventId: 'event',
  circleId: 'circle',
  circleName: '測試圈圈',
  creatorUserId: 'friend',
  creatorNickname: '同好',
  latitude: 25,
  longitude: 121,
  description: description,
  meetAt: at ?? _now.add(const Duration(minutes: 30)),
  createdAt: _now,
  isMine: mine,
);

RecognitionRequest _recognition({
  String id = 'request',
  int day = 2,
  RecognitionStatus status = RecognitionStatus.pending,
  DateTime? created,
  DateTime? replied,
  DateTime? expiry,
  bool requester = false,
}) => RecognitionRequest(
  id: id,
  eventId: 'event',
  dayIndex: day,
  requesterUserId: 'me',
  requesterNickname: '我',
  targetUserId: 'friend',
  targetNickname: '同好',
  status: status,
  createdAt: created ?? _now.subtract(const Duration(minutes: 1)),
  respondedAt: replied,
  expiresAt: expiry,
  isRequester: requester,
  isTarget: !requester,
);

CosEvent _event({String id = 'event', List<int> joined = const [1, 2]}) =>
    CosEvent(
      id: id,
      name: '兩日活動',
      category: '同人活動',
      startDate: DateTime(2026, 10, 27),
      endDate: DateTime(2026, 10, 28),
      venue: '',
      detailedAddress: '',
      fee: '',
      organizer: '',
      description: '',
      isJoined: true,
      joinedDayIndexes: joined,
    );

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 201;
  Object body = {
    'id': 'meetup',
    'push': {'sent': 0, 'failed': 0},
  };
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final signal = entered;
    if (signal != null && !signal.isCompleted) signal.complete();
    await release?.future;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Q16 first load and new meetup polling stay silent; FCM routes creation',
    () {
      final snapshot = MeetupSnapshot();
      expect(snapshot.update([_meetup()], _now), isEmpty);
      expect(snapshot.update([_meetup(), _meetup(id: 'new')], _now), isEmpty);
      expect(
        currentEventNotificationTarget({
          'type': 'meetup_created',
          'meetupId': 'new',
          'eventId': 'event',
          'dayIndex': '2',
        }),
        '/current/event?dayIndex=2',
      );
      final history = NotificationDeliveryHistory();
      expect(history.claim('meetup_created:new'), isTrue);
      expect(history.claim('meetup_created:new'), isFalse);
      history.forget('meetup_created:new');
      expect(history.claim('meetup_created:new'), isTrue);
    },
  );

  test(
    'Q17 failure preserves snapshot; recovery alone cannot cancel a meetup',
    () {
      final snapshot = MeetupSnapshot();
      snapshot.update([_meetup()], _now);
      expect(snapshot.update(null, _now), isEmpty);
      expect(snapshot.items.single.id, 'meetup');
      expect(snapshot.update([_meetup()], _now), isEmpty);
      expect(snapshot.update([_meetup(description: '南門')], _now), [
        '測試圈圈 更改了集合位置',
      ]);
      expect(snapshot.update([], _now), ['測試圈圈 取消了集合']);
      expect(snapshot.update([], _now), isEmpty);
    },
  );

  test(
    'Q18 excludes previous Taipei date and expired points at day boundary',
    () {
      final midnight = DateTime.utc(2026, 10, 27, 16, 1);
      expect(
        _meetup(at: DateTime.utc(2026, 10, 27, 15, 59)).isActiveAt(midnight),
        isFalse,
      );
      expect(
        _meetup(at: DateTime.utc(2026, 10, 27, 16, 5)).isActiveAt(midnight),
        isTrue,
      );
      expect(
        _meetup(
          at: _now.subtract(const Duration(minutes: 10)),
        ).isActiveAt(_now),
        isFalse,
      );
      final snapshot = MeetupSnapshot();
      snapshot.update([
        _meetup(at: DateTime.utc(2026, 10, 27, 15, 59)),
      ], midnight);
      expect(snapshot.update([], midnight), isEmpty);
    },
  );

  testWidgets('Q18 meetup card displays Taipei date and time from ISO Z', (
    tester,
  ) async {
    final meetup = MeetupPoint.fromJson({
      'id': 'm',
      'eventId': 'event',
      'circleId': 'circle',
      'latitude': 25,
      'longitude': 121,
      'meetAt': '2026-10-27T16:30:00Z',
      'createdAt': '2026-10-27T16:00:00Z',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeetupNoticeCard(meetup: meetup, onNavigate: () {}),
        ),
      ),
    );
    expect(find.textContaining('10/28 00:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Q19 expired, cancelled, previous day and old replies never become notices',
    () {
      final requests = [
        _recognition(status: RecognitionStatus.expired, requester: true),
        _recognition(status: RecognitionStatus.cancelled, requester: true),
        _recognition(
          day: 1,
          status: RecognitionStatus.accepted,
          requester: true,
          replied: _now,
        ),
        _recognition(
          status: RecognitionStatus.accepted,
          requester: true,
          created: _now.subtract(const Duration(days: 1)),
          replied: _now,
        ),
        _recognition(
          status: RecognitionStatus.declined,
          requester: true,
          replied: _now.subtract(const Duration(minutes: 15)),
        ),
        _recognition(expiry: _now),
      ];
      expect(selectRecognitionNotice(requests, dayIndex: 2, now: _now), isNull);
      final reply = _recognition(
        id: 'reply',
        status: RecognitionStatus.accepted,
        requester: true,
        replied: _now,
      );
      final pending = _recognition(id: 'pending');
      expect(
        selectRecognitionNotice([reply, pending], dayIndex: 2, now: _now)?.id,
        'pending',
      );
      expect(
        selectRecognitionNotice(
          [reply],
          dayIndex: 2,
          now: _now,
          dismissed: {'reply'},
        ),
        isNull,
      );
      expect(
        selectRecognitionNotice([reply], dayIndex: 2, now: _now)?.id,
        'reply',
      );
    },
  );

  testWidgets('Q19 reply fallback is meaningful and dismiss action is usable', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecognitionNoticeCard(
            request: _recognition(
              status: RecognitionStatus.accepted,
              requester: true,
              replied: _now,
            ),
            onCome: () {},
            onBusy: () {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    expect(find.text('快來'), findsOneWidget);
    await tester.tap(find.byTooltip('關閉認親回覆'));
    expect(dismissed, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Q19 API retains dayIndex, expiry and reply instants', () {
    final request = RecognitionRequest.fromJson({
      'id': 'r',
      'eventId': 'event',
      'dayIndex': 2,
      'status': 'accepted',
      'isRequester': 1,
      'createdAt': '2026-10-27T16:00:00Z',
      'expiresAt': '2026-10-27T16:05:00Z',
      'respondedAt': '2026-10-27T16:02:00Z',
    });
    expect(request.dayIndex, 2);
    expect(request.effectiveExpiry.toUtc(), DateTime.utc(2026, 10, 27, 16, 5));
    expect(request.isNoticeAt(DateTime.utc(2026, 10, 27, 16, 3), 2), isTrue);
  });

  test(
    'Q20 response notifications route to event day and reject incomplete payloads',
    () {
      expect(
        currentEventNotificationTarget({
          'type': 'recognition_response',
          'requestId': 'r',
          'eventId': 'event',
          'dayIndex': '2',
          'status': 'accepted',
        }),
        '/current/event?dayIndex=2',
      );
      for (final data in <Map<String, dynamic>>[
        {'type': 'unknown', 'eventId': 'event', 'dayIndex': 1},
        {'type': 'recognition_response', 'dayIndex': 1},
        {'type': 'recognition_response', 'eventId': 'event', 'dayIndex': 0},
        {'type': 'meetup_created', 'eventId': 'event'},
      ]) {
        expect(currentEventNotificationTarget(data), isNull);
      }
    },
  );

  test(
    'Q21 registration failure remains disabled and same-token retry succeeds',
    () async {
      final adapter = _Adapter()..status = 503;
      final api = ApiClient(
        baseUrl: 'https://example.invalid/api',
        adapter: adapter,
      )..setAuthToken('account-a');
      final session = api.captureSession();
      final registration = PushTokenRegistration(api);
      await expectLater(
        registration.sync('device', 'android', session),
        throwsA(isA<DioException>()),
      );
      expect(registration.registeredToken, isNull);
      adapter.status = 201;
      await registration.sync('device', 'android', session);
      expect(registration.registeredToken, 'device');
      await registration.sync('device', 'android', session);
      expect(adapter.requests, hasLength(2));
      session.cancel();
      expect(registration.registeredToken, isNull);
    },
  );

  for (final accountSwitch in [false, true]) {
    test(
      'Q21 pending registration cannot survive ${accountSwitch ? 'account switch' : 'session disposal'}',
      () async {
        final adapter = _Adapter()
          ..entered = Completer<void>()
          ..release = Completer<void>();
        final api = ApiClient(
          baseUrl: 'https://example.invalid/api',
          adapter: adapter,
        )..setAuthToken('account-a');
        final session = api.captureSession();
        final registration = PushTokenRegistration(api);
        final pending = registration.sync('device', 'android', session);
        final rejected = expectLater(
          pending,
          throwsA(anyOf(isA<DioException>(), isA<StateError>())),
        );
        await adapter.entered!.future;
        if (accountSwitch) {
          api.setAuthToken('account-b');
        } else {
          session.cancel();
        }
        adapter.release!.complete();
        await rejected;
        expect(registration.registeredToken, isNull);
        expect(
          adapter.requests.single.headers['Authorization'],
          'Bearer account-a',
        );
        if (accountSwitch) {
          await registration.sync('device', 'android', api.captureSession());
          expect(registration.registeredToken, 'device');
          expect(
            adapter.requests.last.headers['Authorization'],
            'Bearer account-b',
          );
        }
      },
    );
  }

  test(
    'Q22 stale D1 advances to joined D2 at Taipei midnight in a UTC runtime',
    () {
      const target = CurrentEventTarget(eventId: 'event', dayIndex: 1);
      final events = [_event()];
      expect(
        resolveCurrentEventDay(
          events,
          target,
          DateTime.utc(2026, 10, 27, 15, 59),
        )?.dayIndex,
        1,
      );
      expect(
        resolveCurrentEventDay(
          events,
          target,
          DateTime.utc(2026, 10, 27, 16),
        )?.dayIndex,
        2,
      );
      expect(
        resolveCurrentEventDay(
          [
            _event(joined: [1]),
          ],
          target,
          _now,
        ),
        isNull,
      );
      expect(
        resolveCurrentEventDay(
          [
            _event(id: 'other', joined: [2]),
          ],
          target,
          _now,
        )?.event.id,
        'other',
      );
    },
  );

  test(
    'Q16/Q18 create response with no recipients succeeds and sends ISO UTC times',
    () async {
      final adapter = _Adapter();
      final api = ApiClient(
        baseUrl: 'https://example.invalid/api',
        adapter: adapter,
      );
      final repository = ApiLocationRepository(apiClient: api);
      final time = DateTime.parse('2026-10-28T13:30:00+08:00');
      await repository.createMeetup(
        eventId: 'event',
        circleId: 'circle',
        latitude: 25,
        longitude: 121,
        description: '北門',
        meetAt: time,
      );
      adapter.status = 204;
      await repository.updateMeetup(
        eventId: 'event',
        meetupId: 'meetup',
        circleId: 'circle',
        latitude: 25,
        longitude: 121,
        description: '南門',
        meetAt: time,
      );
      await repository.respondRecognition(
        requestId: 'request',
        status: RecognitionStatus.accepted,
      );
      expect(adapter.requests[0].data['meetAt'], '2026-10-28T05:30:00.000Z');
      expect(adapter.requests[1].data['meetAt'], '2026-10-28T05:30:00.000Z');
      expect(adapter.requests[2].path, '/recognitions/request/respond');
      expect(adapter.requests[2].data, {'status': 'accepted'});
    },
  );
}
