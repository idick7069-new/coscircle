import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/booking.dart';
import 'package:coscircle/core/models/circle.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/event_day_item.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/core/services/auth_state.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/core/utils/public_app_link.dart';
import 'package:coscircle/core/utils/app_qr_code.dart';
import 'package:coscircle/core/utils/upload_image_data.dart';
import 'package:coscircle/features/events/presentation/event_booking_share_page.dart';
import 'package:coscircle/features/events/presentation/event_list_page.dart';
import 'package:coscircle/features/events/presentation/my_events_page.dart';
import 'package:coscircle/features/home/presentation/home_shell_page.dart';
import 'package:coscircle/features/profile/presentation/onboarding_profile_page.dart';
import 'package:coscircle/features/profile/presentation/profile_page.dart';
import 'package:coscircle/features/social/presentation/social_page.dart';
import 'package:coscircle/shared/widgets/cos_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

CosEvent sampleEvent({bool past = false}) {
  final now = DateTime.now();
  final start = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(Duration(days: past ? -5 : 2));
  return CosEvent(
    id: 'qa',
    name: 'QA event with a very long title',
    category: '綜合',
    startDate: start,
    endDate: start.add(const Duration(days: 2)),
    venue: '展覽館',
    detailedAddress: '活動地址',
    fee: '',
    organizer: '',
    description: '',
    isJoined: true,
    joinedDayIndexes: const [1],
    followedDayIndexes: const [2],
  );
}

final sampleParticipant = EventParticipant.fromJson({
  'userId': 'me',
  'nickname': 'QA',
  'role': 'coser',
  'dayIndex': 1,
  'characterName': 'D1 character',
  'isMe': 1,
});

class FixtureEvents extends InMemoryEventRepository {
  FixtureEvents({this.broken = false, this.past = false});
  final bool broken;
  final bool past;
  @override
  Future<List<CosEvent>> fetchEvents() async {
    if (broken) throw Exception('連線失敗');
    return [sampleEvent(past: past)];
  }

  @override
  Future<List<EventParticipant>> fetchParticipants(String id) async => [
    sampleParticipant,
  ];
  @override
  Future<Map<String, List<EventParticipant>>> fetchMyBookings() async => {
    'qa': [sampleParticipant],
  };
}

class FixtureProfile extends InMemoryProfileRepository {
  FixtureProfile({this.broken = false});
  final bool broken;
  UserProfile profile = const UserProfile(
    id: 'me',
    publicCode: 'qa-profile',
    nickname: 'QA nickname',
    profileRoles: ['coser', 'photographer', 'manager', 'self'],
  );
  @override
  Future<UserProfile?> currentProfile() async {
    if (broken) throw Exception('連線失敗');
    return profile;
  }

  @override
  Future<UserProfile> saveProfile(UserProfile value) async => profile = value;
}

class FixtureSocial extends SocialRepository {
  FixtureSocial()
    : super(apiClient: ApiClient(baseUrl: 'http://34.187.168.222/api'));
  @override
  Future<List<CircleGroup>> fetchCircles() async => const [
    CircleGroup(
      id: 'qa',
      name: 'QA circle',
      inviteCode: 'QA123',
      inviteUrl: 'http://34.187.168.222/app/#/join/QA123',
      memberCount: 1,
      isOwner: true,
      members: [
        CircleMember(
          userId: 'me',
          publicCode: 'qa-profile',
          nickname: 'QA',
          isOwner: true,
        ),
      ],
    ),
  ];
  @override
  Future<List<FollowedUser>> fetchFollowing() async => const [];
}

class FailingApi extends ApiClient {
  FailingApi(this.status) : super(baseUrl: 'http://34.187.168.222/api');
  final int? status;
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final options = RequestOptions(path: path);
    throw DioException(
      requestOptions: options,
      type: status == null
          ? DioExceptionType.connectionError
          : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response(requestOptions: options, statusCode: status),
    );
  }
}

Widget host(
  Widget page, {
  double scale = 1,
  bool dark = true,
  ProfileRepository? profile,
  EventRepository? events,
}) => ProviderScope(
  overrides: [
    profileRepositoryProvider.overrideWithValue(profile ?? FixtureProfile()),
    eventRepositoryProvider.overrideWithValue(events ?? FixtureEvents()),
    socialRepositoryProvider.overrideWithValue(FixtureSocial()),
  ],
  child: RepaintBoundary(
    key: const ValueKey('qa-screen'),
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: page),
    ),
  ),
);

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('QA_SCREENSHOTS')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('qa-screen')),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/coscircle-qa-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('personal QR fits $size text=$scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(host(const ProfilePage(), scale: scale));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('分享個人資訊'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final qr = find.byType(QrImageView).last;
        expect(qr, findsOneWidget);
        expect(tester.getSize(qr).width, lessThanOrEqualTo(210));
        expect(tester.getSize(qr).width, tester.getSize(qr).height);
        await tester.ensureVisible(find.byType(SelectableText).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final item in {
    '暱稱': '暱稱',
    '頭像': '上傳頭像',
    '自介': '自我介紹',
    '身份': '身份',
    '座標': '座標',
    '跑場': '跑場範圍',
    '深坑': '深坑',
    '淺坑': '淺坑',
    '照片': '其他照片',
  }.entries) {
    testWidgets('readiness opens editable ${item.key}', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(const ProfilePage()));
      await tester.pumpAndSettle();
      final chip = find.byKey(ValueKey('profile-readiness-${item.key}'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final label = item.key == '頭像'
          ? find.byTooltip(item.value)
          : find.text(item.value).last;
      expect(label, findsOneWidget);
      final bounds = tester.getRect(label);
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('booking image has one fixed share action', (tester) async {
    await tester.pumpWidget(
      host(
        EventBookingSharePage(
          event: sampleEvent(),
          bookings: [sampleParticipant],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.text('分享圖片').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('分享圖片').hitTestable(), findsOneWidget);
    expect(find.text('產生並分享圖片'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('event discovery summary stays compact', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(EventListPage(onOpenCurrentEvent: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('今天想在哪裡認親？'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('event-discovery-summary')))
          .height,
      lessThanOrEqualTo(100),
    );
    expect(tester.takeException(), isNull);
  });
  test('QR scanner supports web fragments and legacy links', () {
    expect(
      extractAppQrCode(
        'https://example.com/app/#/profiles/PROFILE123',
        'profiles',
        minimumLength: 8,
      ),
      'PROFILE123',
    );
    expect(
      extractAppQrCode(
        'coscircle://profiles/PROFILE123',
        'profiles',
        minimumLength: 8,
      ),
      'PROFILE123',
    );
    expect(
      extractAppQrCode('https://example.com/app/#/join/CIRCLE123', 'join'),
      'CIRCLE123',
    );
    expect(
      extractAppQrCode('https://coscircle.local/join/CIRCLE123', 'join'),
      'CIRCLE123',
    );
    expect(
      extractAppQrCode('https://example.com/app/#/join/%2Fbad', 'join'),
      isNull,
    );
    expect(extractAppQrCode('https://example.com/else', 'join'), isNull);
  });
  setUpAll(() async {
    await initializeDateFormatting('zh_TW');
    for (final entry in {
      'Roboto': const String.fromEnvironment('QA_LATIN_FONT'),
      'Noto Sans TC': const String.fromEnvironment('QA_CJK_FONT'),
    }.entries) {
      if (entry.value.isEmpty) continue;
      final loader = FontLoader(entry.key)
        ..addFont(
          Future.value(
            ByteData.sublistView(await File(entry.value).readAsBytes()),
          ),
        );
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sessionExpired.value = false;
  });
  test('network failure preserves session; explicit 401 clears it', () async {
    for (final status in [null, 500, 401]) {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'synthetic-qa-token',
      });
      final auth = AuthRepository(apiClient: FailingApi(status));
      if (status == 401) {
        expect(await auth.restoreToken(), isNull);
      } else {
        await expectLater(auth.restoreToken(), throwsA(isA<DioException>()));
      }
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        status == 401 ? isNull : 'synthetic-qa-token',
      );
    }
  });
  test('day bookings and social signals remain independent', () async {
    final repository = InMemoryEventRepository();
    await repository.upsertBooking(
      const EventBooking(
        eventId: 'qa',
        role: ParticipantRole.coser,
        dayIndex: 1,
        characterName: 'D1',
      ),
    );
    await repository.upsertBooking(
      const EventBooking(
        eventId: 'qa',
        role: ParticipantRole.photographer,
        dayIndex: 2,
        characterName: 'D2',
      ),
    );
    await repository.removeBooking('qa', dayIndex: 1);
    final mine = await repository.fetchMyBookings();
    expect(mine['qa']!.single.dayIndex, 2);
    expect(mine['qa']!.single.characterName, 'D2');
    final days = expandEventDays([sampleEvent()]);
    expect(days.map((d) => d.hasFollowedParticipants), [false, true, false]);
  });
  test(
    'image MIME uses bytes even for blob paths; oversized images fail',
    () async {
      final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]);
      final parsed = await readUploadImage(
        XFile.fromData(
          png,
          name: 'blob-file',
          mimeType: 'application/octet-stream',
        ),
      );
      expect(parsed.mimeType, 'image/png');
      await expectLater(
        readUploadImage(XFile.fromData(Uint8List(5 * 1024 * 1024 + 1))),
        throwsException,
      );
      await expectLater(
        readUploadImage(XFile.fromData(Uint8List.fromList([1, 2, 3]))),
        throwsException,
      );
    },
  );
  test('share links have a browser fallback and safe return paths', () {
    expect(publicAppLink('/profiles/abc'), endsWith('/app/#/profiles/abc'));
    expect(safeReturnPath('https://example.com'), '/');
    expect(safeReturnPath('//example.com'), '/');
    expect(safeReturnPath('/join/QA'), '/join/QA');
  });
  testWidgets('failed profile load cannot edit or overwrite data', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const ProfilePage(), profile: FixtureProfile(broken: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('重試'), findsOneWidget);
    expect(find.byTooltip('編輯'), findsNothing);
  });
  testWidgets('failed my events shows retry rather than infinite loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MyEventsPage(), events: FixtureEvents(broken: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('重試'), findsOneWidget);
    expect(find.text('同步參戰名片'), findsNothing);
  });
  testWidgets('editing D1 cannot switch and overwrite D2', (tester) async {
    await tester.pumpWidget(
      host(
        BookingSheet(
          event: sampleEvent(),
          initialParticipant: sampleParticipant,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final d2 = find.widgetWithText(
      CosChoicePill,
      'D2 · ${sampleEvent().startDate.add(const Duration(days: 1)).month.toString().padLeft(2, '0')}/${sampleEvent().startDate.add(const Duration(days: 1)).day.toString().padLeft(2, '0')}',
    );
    expect(tester.widget<CosChoicePill>(d2).enabled, isFalse);
    await tester.ensureVisible(d2);
    await tester.tap(d2, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('D1 character'), findsOneWidget);
    expect(find.text('D2'), findsNothing);
  });
  testWidgets('historical bookings cannot edit or cancel', (tester) async {
    await tester.pumpWidget(
      host(const MyEventsPage(), events: FixtureEvents(past: true)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('顯示已過期'));
    await tester.tap(find.text('顯示已過期'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('修改'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('修改'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '取消預訂',
            ),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('tab changes preserve unsaved profile text', (tester) async {
    await tester.pumpWidget(host(const HomeShellPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名片'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    final nickname = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '暱稱',
    );
    await tester.ensureVisible(nickname);
    await tester.enterText(nickname, 'draft nickname');
    await tester.tap(find.text('活動').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('名片'));
    await tester.pumpAndSettle();
    expect(find.text('draft nickname'), findsOneWidget);
  });
  final pages = <String, Widget Function()>{
    'profile': () => const ProfilePage(),
    'events': () => EventListPage(onOpenCurrentEvent: (_) {}),
    'booking': () => BookingSheet(
      event: sampleEvent(),
      initialParticipant: sampleParticipant,
    ),
    'onboarding': () => const OnboardingProfilePage(),
    'social': () => const SocialPage(),
    'share': () => EventBookingSharePage(
      event: sampleEvent(),
      bookings: [sampleParticipant],
    ),
  };
  for (final dark in [true, false]) {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final entry in pages.entries) {
          testWidgets(
            'layout ${entry.key} width=$width text=$scale dark=$dark',
            (tester) async {
              tester.view.physicalSize = Size(width, 844);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.pumpWidget(
                host(entry.value(), scale: scale, dark: dark),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              if (dark && width == 320 && scale == 2) {
                await screenshot(tester, entry.key);
              }
              if (entry.key == 'profile') {
                await tester.tap(find.byTooltip('編輯'));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                if (dark && width == 320 && scale == 2) {
                  await screenshot(tester, 'profile-edit');
                }
              }
              if (entry.key == 'onboarding') {
                while (find.text('下一步').evaluate().isNotEmpty) {
                  await tester.tap(find.text('下一步'));
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                }
                if (dark && width == 320 && scale == 2) {
                  await screenshot(tester, 'onboarding-setup');
                }
              }
              for (var step = 0; step < 5; step++) {
                final scrollables = find.byType(Scrollable);
                if (scrollables.evaluate().isEmpty) break;
                await tester.drag(scrollables.first, const Offset(0, -500));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
              await tester.pumpWidget(const SizedBox());
              await tester.pumpAndSettle();
            },
          );
        }
      }
    }
  }
}
