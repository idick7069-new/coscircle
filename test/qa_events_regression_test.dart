import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscircle/core/models/booking.dart';
import 'package:coscircle/core/models/circle.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/providers/event_providers.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/utils/picked_image_provider_io.dart' as native;
import 'package:coscircle/core/utils/picked_image_provider_web.dart' as web;
import 'package:coscircle/features/events/presentation/event_booking_share_page.dart';
import 'package:coscircle/features/events/presentation/event_detail_page.dart';
import 'package:coscircle/features/events/presentation/event_list_page.dart';
import 'package:coscircle/features/events/presentation/my_events_page.dart';
import 'package:coscircle/features/social/presentation/social_page.dart'
    show followingProvider;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

const _character = '這是一個很長的預設角色名稱';

CosEvent _event({bool followed = false}) {
  final start = DateTime.now().add(const Duration(days: 10));
  return CosEvent(
    id: 'qa-events',
    name: '活動回歸測試',
    category: '同人活動',
    startDate: DateTime(start.year, start.month, start.day),
    endDate: DateTime(start.year, start.month, start.day + 2),
    venue: '測試會場',
    detailedAddress: '',
    fee: '',
    organizer: '',
    description: '',
    isJoined: true,
    joinedDayIndexes: const [1, 2, 3],
    hasFollowedParticipants: followed,
    followedDayIndexes: followed ? const [1] : const [],
  );
}

EventParticipant _participant(int day) => EventParticipant(
  userId: 'me',
  nickname: 'QA',
  role: 'coser',
  dayIndex: day,
  characterName: _character,
  isMe: true,
  isFollowed: true,
);

class _Events extends InMemoryEventRepository {
  _Events(this.event);
  final CosEvent event;
  Completer<void>? pendingSave;
  final savedBookings = <EventBooking>[];

  @override
  Future<List<CosEvent>> fetchEvents() async => [event];
  @override
  Future<List<EventParticipant>> fetchParticipants(String eventId) async => [
    for (var day = 1; day <= 3; day++) _participant(day),
  ];
  @override
  Future<Map<String, List<EventParticipant>>> fetchMyBookings() async => {
    event.id: await fetchParticipants(event.id),
  };
  @override
  Future<void> upsertBooking(EventBooking booking) async {
    savedBookings.add(booking);
    await pendingSave?.future;
  }
}

class _RelationshipEvents extends _Events {
  _RelationshipEvents() : super(_event());

  bool followed = false;
  bool blocked = false;

  @override
  Future<List<CosEvent>> fetchEvents() async => [_event(followed: followed)];

  @override
  Future<List<EventParticipant>> fetchParticipants(String eventId) async => [
    if (!blocked)
      EventParticipant(
        userId: 'peer',
        nickname: '測試同好',
        role: 'coser',
        dayIndex: 1,
        isFollowed: followed,
      ),
  ];

  @override
  Future<void> followUser(String userId) async {
    expect(userId, 'peer');
    followed = true;
  }

  @override
  Future<void> unfollowUser(String userId) async {
    expect(userId, 'peer');
    followed = false;
  }

  @override
  Future<void> blockUser(String userId) async {
    expect(userId, 'peer');
    blocked = true;
    followed = false;
  }
}

Widget _host(Widget page, _Events repository) => ProviderScope(
  overrides: [eventRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    locale: const Locale('zh', 'TW'),
    supportedLocales: const [Locale('zh', 'TW')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: page),
  ),
);

Finder _canvas() => find.byWidgetPredicate(
  (widget) =>
      widget is RepaintBoundary &&
      widget.child is SizedBox &&
      (widget.child! as SizedBox).width == 1800,
);

Finder _labelFields() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == '角色名文字',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_TW'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Q24 native and web preserve upload origin, port and signed query', () {
    for (final origin in [
      'http://localhost:8080',
      'http://127.0.0.1:4000',
      'http://10.0.2.2:8080',
      'https://192.168.5.198:9443',
      'http://172.20.0.3:3000',
      'https://media.example.com',
    ]) {
      final url = '$origin/uploads/a.png?signature=abc%2Fdef#preview';
      expect((native.pickedImageProvider(url)! as NetworkImage).url, url);
      expect((web.pickedImageProvider(url)! as NetworkImage).url, url);
    }
    expect(native.pickedImageProvider(''), isNull);
    expect(web.pickedImageProvider(''), isNull);
    expect(native.pickedImageProvider('/tmp/outfit.png'), isA<FileImage>());
    expect(
      (web.pickedImageProvider('blob:https://example.com/image')!
              as NetworkImage)
          .url,
      'blob:https://example.com/image',
    );
  });

  for (final fromMyEvents in [false, true]) {
    testWidgets(
      'Q07 dismissal guards from ${fromMyEvents ? 'my events' : 'detail'}',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final event = _event();
        final repository = _Events(event);
        await tester.pumpWidget(
          _host(
            fromMyEvents
                ? const MyEventsPage()
                : EventDetailPage(eventId: event.id),
            repository,
          ),
        );
        await tester.pumpAndSettle();
        final edit = fromMyEvents
            ? find.text('修改').first
            : find.byKey(const ValueKey('detail-booking-1'));
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(find.byType(BookingSheet), findsOneWidget);
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.enableDrag, isFalse);
        expect(sheet.showDragHandle, isFalse);
        final character = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '角色名',
        );
        await tester.ensureVisible(character);
        await tester.enterText(character, '保留草稿');
        await tester.pumpAndSettle();
        await tester.drag(find.byType(BookingSheet), const Offset(0, 700));
        await tester.pumpAndSettle();
        expect(find.byType(BookingSheet), findsOneWidget);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.text('捨棄未儲存的預定？'), findsOneWidget);
        await tester.tap(find.text('繼續編輯'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(character).controller!.text, '保留草稿');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('捨棄未儲存的預定？'), findsOneWidget);
        await tester.tap(find.text('繼續編輯'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(character).controller!.text, '保留草稿');
        final close = find.byTooltip('關閉');
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        await tester.tap(find.text('捨棄'));
        await tester.pumpAndSettle();
        expect(find.byType(BookingSheet), findsNothing);
        expect(repository.savedBookings, isEmpty);

        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('關閉'));
        await tester.pumpAndSettle();
        expect(find.byType(BookingSheet), findsNothing);
        expect(find.text('捨棄未儲存的預定？'), findsNothing);

        final pendingSave = Completer<void>();
        repository.pendingSave = pendingSave;
        addTearDown(() {
          if (!pendingSave.isCompleted) pendingSave.complete();
        });
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.ensureVisible(character);
        await tester.enterText(character, '儲存中的草稿');
        final save = find.text('儲存出席');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.tapAt(const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(BookingSheet), findsOneWidget);
        expect(find.text('捨棄未儲存的預定？'), findsNothing);
        expect(repository.savedBookings.single.characterName, '儲存中的草稿');
        expect(repository.savedBookings.single.dayIndex, 1);
        pendingSave.complete();
        await tester.pumpAndSettle();
        expect(find.byType(BookingSheet), findsNothing);
        expect(repository.savedBookings, hasLength(1));
      },
    );
  }

  testWidgets(
    'Q09 participant count is unique and each day has its date and count',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final event = _event();
      await tester.pumpWidget(
        _host(EventDetailPage(eventId: event.id), _Events(event)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('現場同好'));
      await tester.pumpAndSettle();
      expect(find.text('1 位'), findsOneWidget);
      expect(find.text('3 位'), findsNothing);
      for (var day = 1; day <= 3; day++) {
        final date = event.startDate.add(Duration(days: day - 1));
        expect(
          find.text(
            'D$day · ${DateFormat('MM/dd', 'zh_TW').format(date)} · 1 位',
          ),
          findsOneWidget,
        );
      }
      final avatars = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.child is SizedBox &&
            (widget.child! as SizedBox).width == 86,
      );
      await tester.ensureVisible(avatars.at(1));
      await tester.tap(avatars.at(1));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'D2 · ${DateFormat('yyyy/MM/dd', 'zh_TW').format(event.startDate.add(const Duration(days: 1)))}',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Q12 detail follow, unfollow and block refresh cached following and event filters',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _RelationshipEvents();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(repository),
            followingProvider.overrideWith(
              (ref) async => [
                if (repository.followed)
                  const FollowedUser(
                    userId: 'peer',
                    publicCode: 'peer-code',
                    nickname: '測試同好',
                  ),
              ],
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh', 'TW'),
            supportedLocales: const [Locale('zh', 'TW')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: EventDetailPage(eventId: repository.event.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EventDetailPage)),
      );
      final following = container.listen(followingProvider, (_, _) {});
      addTearDown(following.close);
      expect(await container.read(followingProvider.future), isEmpty);
      expect(
        (await container.read(eventsProvider.future)).single.followedDayIndexes,
        isEmpty,
      );

      final avatar = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.child is SizedBox &&
            (widget.child! as SizedBox).width == 86,
      );
      for (final action in ['關注', '取消關注', '關注']) {
        await tester.ensureVisible(avatar);
        await tester.drag(find.byType(ListView).first, const Offset(0, -180));
        await tester.pumpAndSettle();
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        final button = find.text(action);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final expectedFollowed = action == '關注';
        expect(
          (await container.read(
            followingProvider.future,
          )).map((user) => user.userId),
          expectedFollowed ? ['peer'] : isEmpty,
        );
        expect(
          (await container.read(
            eventsProvider.future,
          )).single.followedDayIndexes,
          expectedFollowed ? [1] : isEmpty,
        );
      }

      await tester.ensureVisible(avatar);
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('封鎖此使用者'));
      await tester.tap(find.text('封鎖此使用者'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('封鎖').last);
      await tester.pumpAndSettle();
      expect(await container.read(followingProvider.future), isEmpty);
      expect(
        (await container.read(eventsProvider.future)).single.followedDayIndexes,
        isEmpty,
      );
      expect(avatar, findsNothing);
      expect(find.text('目前沒有可顯示的預定。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Q13 Q23 browsing month survives filter rebuild and recreation in Chinese',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Events(_event());
      Widget page() =>
          _host(EventListPage(onOpenCurrentEvent: (_) {}), repository);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final calendar = find.byWidgetPredicate(
        (widget) => widget is TableCalendar,
      );
      final initial = tester.widget<TableCalendar>(calendar).focusedDay;
      final forward = initial.month == 12
          ? Icons.chevron_left
          : Icons.chevron_right;
      final chevron = find.descendant(
        of: calendar,
        matching: find.byIcon(forward),
      );
      await tester.tap(chevron);
      await tester.pumpAndSettle();
      final target = DateTime(
        initial.year,
        initial.month + (initial.month == 12 ? -1 : 1),
        1,
      );
      await tester.ensureVisible(find.text('關注者').last);
      await tester.tap(find.text('關注者').last);
      await tester.pumpAndSettle();
      final updated = tester.widget<TableCalendar>(calendar);
      expect(updated.locale, 'zh_TW');
      expect(updated.focusedDay.month, target.month);
      expect(updated.selectedDayPredicate!(target), isFalse);
      expect(
        find.text(DateFormat.yMMMM('zh_TW').format(target)),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TableCalendar>(calendar).focusedDay.month,
        target.month,
      );
    },
  );

  testWidgets(
    'Q08 long labels fit, empty days have no label, clearing stays empty',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final event = _event();
      await tester.pumpWidget(
        _host(
          EventBookingSharePage(event: event, bookings: [_participant(1)]),
          _Events(event),
        ),
      );
      await tester.pumpAndSettle();
      final label = find.descendant(
        of: _canvas(),
        matching: find.text(_character),
      );
      final fit = find
          .ancestor(of: label, matching: find.byType(FittedBox))
          .first;
      final labelRect = tester.getRect(label);
      final fitRect = tester.getRect(fit);
      expect(labelRect.width, lessThanOrEqualTo(fitRect.width + 0.01));
      expect(labelRect.left, greaterThanOrEqualTo(fitRect.left - 0.01));
      Finder backgrounds() => find.descendant(
        of: _canvas(),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  const Color(0xff111111),
        ),
      );
      expect(backgrounds(), findsOneWidget);
      final field = _labelFields().first;
      await tester.ensureVisible(field);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _canvas(), matching: find.text(_character)),
        findsNothing,
      );
      expect(backgrounds(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Q10 sharing selected layer exports the clean painted PNG', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync(
      'coscircle-events-export-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    Uint8List? exported;
    messenger.setMockMethodCallHandler(pathChannel, (_) async => temp.path);
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      final args = call.arguments as Map;
      exported = File(
        (args['paths'] as List).single as String,
      ).readAsBytesSync();
      return 'qa-share';
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(pathChannel, null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });
    final event = _event();
    await tester.pumpWidget(
      _host(
        EventBookingSharePage(event: event, bookings: [_participant(1)]),
        _Events(event),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(_canvas());
    final baseline = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    await tester.tap(
      find.descendant(of: _canvas(), matching: find.text(_character)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _canvas(), matching: find.byIcon(Icons.open_with)),
      findsOneWidget,
    );
    await tester.tap(find.text('分享圖片'));
    await tester.pump();
    for (var attempt = 0; exported == null && attempt < 100; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(exported, isNotNull);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(exported!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 3600);
      expect(frame.image.height, 2400);
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels!.buffer.asUint8List(), orderedEquals(baseline!));
      frame.image.dispose();
      codec.dispose();
    });
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _canvas(), matching: find.byIcon(Icons.open_with)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
