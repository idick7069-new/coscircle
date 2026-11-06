import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscircle/core/models/booking_visibility.dart';
import 'package:coscircle/core/models/friendship.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/models/same_work_user.dart';
import 'package:coscircle/core/models/work.dart';
import 'package:coscircle/core/providers/same_work_providers.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/features/profile/presentation/profile_page.dart';
import 'package:coscircle/features/profile/presentation/profile_readiness_celebration.dart';
import 'package:coscircle/features/social/presentation/same_work_list.dart';
import 'package:coscircle/shared/widgets/cos_illustration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alpha_regression_test.dart' as qa;

const peer = SameWorkUser(
  userId: '2',
  publicCode: 'peer-two',
  nickname: '同坑攝影',
  commonWorkCount: 1,
  commonWorks: [WorkTag(id: '100', name: '星旅')],
);

class _Profile extends qa.FixtureProfile {
  int saves = 0;
  Completer<UserProfile>? saving;
  @override
  Future<UserProfile> saveProfile(UserProfile value) async {
    saves++;
    if (saving != null) return saving!.future;
    return super.saveProfile(value);
  }

  @override
  Future<List<BookingFollowerGroup>> fetchBookingFollowers() async => [
    BookingFollowerGroup(
      bookingId: '1',
      eventId: 'qa',
      eventName: '測試場次',
      startDate: DateTime(2026, 10, 20),
      endDate: DateTime(2026, 10, 20),
      dayIndex: 1,
      role: 'coser',
      followers: const [BookingFollower(userId: '2', nickname: '測試追蹤者甲')],
    ),
  ];
}

class _Social extends qa.FixtureSocial {
  final requests = <int>[];
  final invites = <String>[];
  final friendships = <Friendship>[];
  Future<SameWorkPage> Function(int)? fetch;
  @override
  Future<SameWorkPage> fetchSameWorkUsers({int offset = 0}) {
    requests.add(offset);
    return fetch?.call(offset) ??
        Future.value(const SameWorkPage(items: [peer]));
  }

  @override
  Future<List<Friendship>> fetchFriendships() async => friendships.toList();
  @override
  Future<String> inviteFriend(
    String userId, {
    required String introduction,
    String? eventId,
    int? dayIndex,
  }) async {
    invites.add(introduction);
    friendships.add(
      Friendship(
        id: 'request',
        userId: userId,
        publicCode: peer.publicCode,
        nickname: peer.nickname,
        status: 'pending',
        introduction: introduction,
        requesterId: 'me',
      ),
    );
    return 'pending';
  }
}

Future<void> _open(
  WidgetTester tester,
  Widget page, {
  _Profile? profile,
  _Social? social,
  double width = 390,
  double scale = 1,
  bool reduceMotion = true,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    final bytes = await rootBundle.load(
      'assets/illustrations/meet-your-circle.png',
    );
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 2,
    );
    final frame = await codec.getNextFrame();
    for (final name in ['avatar', 'photo']) {
      PaintingBinding.instance.imageCache.putIfAbsent(
        NetworkImage('https://example.invalid/$name.png'),
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: frame.image.clone())),
        ),
      );
    }
    frame.image.dispose();
    codec.dispose();
  });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: page),
      ),
      GoRoute(
        path: '/profiles/:code',
        builder: (_, state) =>
            Scaffold(body: Text('公開名片 ${state.pathParameters['code']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profile ?? _Profile()),
        socialRepositoryProvider.overrideWithValue(social ?? _Social()),
        eventRepositoryProvider.overrideWithValue(qa.FixtureEvents()),
      ],
      child: RepaintBoundary(
        key: const ValueKey('refinements-preview'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
          locale: const Locale('zh', 'TW'),
          supportedLocales: const [Locale('zh', 'TW')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_TW');
    if (const bool.fromEnvironment('QA_SCREENSHOTS')) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final entry in {
        'Roboto': const String.fromEnvironment('QA_LATIN_FONT'),
        'Noto Sans TC': const String.fromEnvironment('QA_CJK_FONT'),
      }.entries) {
        if (entry.value.isEmpty) continue;
        await (FontLoader(entry.key)..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            ))
            .load();
      }
    }
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({'auth_token': 'qa-token'}),
  );

  const completeProfile = UserProfile(
    id: 'me',
    nickname: '同好',
    publicCode: 'qa-profile',
    avatarUrl: 'https://example.invalid/avatar.png',
    bio: '喜歡認親',
    profileRoles: ['coser'],
    regions: ['北部'],
    travelRegions: ['北部'],
    deepPitWorks: [WorkTag(id: '1', name: '深坑')],
    shallowPitWorks: [WorkTag(id: '2', name: '淺坑')],
    otherPhotoUrls: ['https://example.invalid/photo.png'],
  );

  testWidgets('readiness celebrates successful incomplete to complete only', (
    tester,
  ) async {
    final profile = _Profile()..profile = completeProfile.copyWith(bio: '');
    await _open(tester, const ProfilePage(), profile: profile);
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
    expect(find.text('認親準備度'), findsOneWidget);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    final bio = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '自我介紹',
    );
    await tester.ensureVisible(bio);
    await tester.enterText(bio, '喜歡認親');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReadinessCelebration), findsOneWidget);
    expect(find.text('恭喜！名片準備好了'), findsOneWidget);
    await tester.tap(find.text('太好了'));
    await tester.pumpAndSettle();
    expect(find.text('認親準備度'), findsNothing);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('complete initial load and cancel do not celebrate', (
    tester,
  ) async {
    await _open(
      tester,
      const ProfilePage(),
      profile: _Profile()..profile = completeProfile,
    );
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
    expect(find.text('認親準備度'), findsNothing);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消編輯'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
  });

  testWidgets('readiness returns when saved profile becomes incomplete', (
    tester,
  ) async {
    await _open(
      tester,
      const ProfilePage(),
      profile: _Profile()..profile = completeProfile,
    );
    expect(find.text('認親準備度'), findsNothing);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    final bio = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '自我介紹',
    );
    await tester.ensureVisible(bio);
    await tester.enterText(bio, '');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('認親準備度'), findsOneWidget);
    expect(find.text('8/9'), findsOneWidget);
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
  });

  testWidgets('failed save never celebrates, successful retry does', (
    tester,
  ) async {
    final profile = _Profile()
      ..profile = completeProfile.copyWith(bio: '')
      ..saving = Completer<UserProfile>();
    await _open(tester, const ProfilePage(), profile: profile);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pump();
    profile.saving!.completeError(Exception('save failed'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
    profile.saving = Completer<UserProfile>();
    await tester.tap(find.text('儲存'));
    await tester.pump();
    profile.saving!.complete(completeProfile);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReadinessCelebration), findsOneWidget);
    await tester.tap(find.text('太好了'));
    await tester.pumpAndSettle();
  });

  for (final hidden in [false, true]) {
    testWidgets(
      'save respects server result and tab visibility hidden=$hidden',
      (tester) async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        final profile = _Profile()
          ..profile = completeProfile.copyWith(bio: '')
          ..saving = Completer<UserProfile>();
        await _open(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, value, _) => ProfilePage(isVisible: value),
          ),
          profile: profile,
        );
        await tester.tap(find.byTooltip('編輯'));
        await tester.pumpAndSettle();
        final bio = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '自我介紹',
        );
        await tester.ensureVisible(bio);
        await tester.enterText(bio, '已完成的草稿');
        await tester.tap(find.text('儲存'));
        await tester.pump();
        if (hidden) {
          visible.value = false;
          await tester.pump();
        }
        profile.saving!.complete(
          hidden ? completeProfile : completeProfile.copyWith(bio: ''),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProfileReadinessCelebration), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pending save after leaving page never shows congratulations', (
    tester,
  ) async {
    final profile = _Profile()
      ..profile = completeProfile.copyWith(bio: '')
      ..saving = Completer<UserProfile>();
    await _open(tester, const ProfilePage(), profile: profile);
    await tester.tap(find.byTooltip('編輯'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    profile.saving!.complete(completeProfile);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReadinessCelebration), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'celebration motion=$reduced fits narrow large-text screen and settles',
      (tester) async {
        await _open(
          tester,
          const ProfileReadinessCelebration(),
          width: 320,
          scale: 2,
          reduceMotion: reduced,
          settle: false,
        );
        expect(find.text('恭喜！名片準備好了'), findsOneWidget);
        final badge = find.byKey(const ValueKey('readiness-celebration-badge'));
        double scale() => tester.widget<Transform>(badge).transform.entry(0, 0);
        expect(scale(), reduced ? 1 : 0.75);
        await tester.pump(const Duration(milliseconds: 250));
        expect(scale(), reduced ? 1 : greaterThan(1));
        if (!reduced && const bool.fromEnvironment('QA_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('refinements-preview')),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/ui-preview').create(recursive: true);
            await File(
              'build/ui-preview/readiness-celebration.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpAndSettle();
        expect(scale(), 1);
        expect(tester.takeException(), isNull);
        expect(find.text('太好了').hitTestable(), findsOneWidget);
      },
    );
  }

  test('same-work JSON keeps stable string IDs and pagination', () {
    final page = SameWorkPage.fromJson({
      'items': [
        {
          'userId': 2,
          'publicCode': 'peer-two',
          'nickname': '同坑攝影',
          'commonWorkCount': '1',
          'commonWorks': [
            {'id': 100, 'name': '星旅'},
          ],
        },
      ],
      'hasMore': true,
      'nextOffset': 20,
    });
    expect(page.items.single.userId, '2');
    expect(page.items.single.commonWorks.single.id, '100');
    expect(page.nextOffset, 20);
  });

  test(
    'refresh discards an older in-flight page after matching data changes',
    () async {
      var initial = true;
      final pending = Completer<SameWorkPage>();
      final social = _Social()
        ..fetch = (offset) {
          if (offset != 0) return pending.future;
          return Future.value(
            initial
                ? const SameWorkPage(items: [peer], nextOffset: 20)
                : const SameWorkPage(items: []),
          );
        };
      final container = ProviderContainer(
        overrides: [socialRepositoryProvider.overrideWithValue(social)],
      );
      addTearDown(container.dispose);
      final listener = container.listen(sameWorkUsersProvider, (_, _) {});
      addTearDown(listener.close);
      await container.read(sameWorkUsersProvider.future);
      final oldPage = container.read(sameWorkUsersProvider.notifier).loadMore();
      initial = false;
      container.invalidate(sameWorkUsersProvider);
      await container.read(sameWorkUsersProvider.future);
      pending.complete(const SameWorkPage(items: [peer]));
      await oldPage;
      expect(container.read(sameWorkUsersProvider).requireValue.items, isEmpty);
    },
  );

  testWidgets(
    'profile illustration is removed and save stays reachable during scrolling and keyboard',
    (tester) async {
      await _open(tester, const ProfilePage(), width: 320, scale: 2);
      expect(find.byType(CosIllustration), findsNothing);
      await tester.tap(find.byTooltip('編輯'));
      await tester.pumpAndSettle();
      final save = find.text('儲存');
      expect(save.hitTestable(), findsOneWidget);
      final before = tester.getRect(
        find.byKey(const ValueKey('profile-save-bar')),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('profile-save-bar'))),
        before,
      );
      expect(save.hitTestable(), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('profile-save-bar'))).bottom,
        lessThanOrEqualTo(544),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final item in {
    'works': '深坑',
    'travel': '跑場範圍',
    'photos': '其他照片',
    'boundaries': '雷點',
  }.entries) {
    testWidgets('signal ${item.key} opens its matching edit section', (
      tester,
    ) async {
      await _open(tester, const ProfilePage());
      final target = find.byKey(ValueKey('profile-signal-${item.key}'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-edit')), findsOneWidget);
      expect(find.text(item.value), findsWidgets);
      expect(find.text('儲存').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'follower details start collapsed and expanding does not open profile editing',
    (tester) async {
      await _open(tester, const ProfilePage());
      expect(find.text('測試追蹤者甲'), findsNothing);
      final expansion = find.byKey(
        const PageStorageKey('booking-followers-expanded'),
      );
      await tester.ensureVisible(expansion);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: expansion, matching: find.text('追蹤者')),
      );
      await tester.pumpAndSettle();
      expect(find.text('測試追蹤者甲'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-edit')), findsNothing);
      await tester.tap(
        find.descendant(of: expansion, matching: find.text('追蹤者')),
      );
      await tester.pumpAndSettle();
      expect(find.text('測試追蹤者甲'), findsNothing);
    },
  );

  testWidgets(
    'failed save keeps draft and re-enables fixed button without duplicate submission',
    (tester) async {
      final profile = _Profile()..saving = Completer<UserProfile>();
      await _open(tester, const ProfilePage(), profile: profile);
      await tester.tap(find.byTooltip('編輯'));
      await tester.pumpAndSettle();
      final nickname = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '暱稱',
      );
      await tester.enterText(nickname, '保留我的暱稱');
      await tester.tap(find.text('儲存'));
      await tester.pump();
      expect(profile.saves, 1);
      expect(find.text('儲存中'), findsOneWidget);
      await tester.tap(find.text('儲存中'));
      await tester.pump();
      expect(profile.saves, 1);
      profile.saving!.completeError(Exception('save failed'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(nickname).controller!.text, '保留我的暱稱');
      expect(find.text('儲存').hitTestable(), findsOneWidget);
      profile.saving = null;
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expect(profile.saves, 2);
      expect(profile.profile.nickname, '保留我的暱稱');
      expect(find.byKey(const ValueKey('profile-save-bar')), findsNothing);
    },
  );

  testWidgets(
    'same-work list shows overlap and opens the correct public card at large text',
    (tester) async {
      await _open(tester, const SameWorkList(), width: 320, scale: 2);
      expect(find.text('同坑攝影'), findsOneWidget);
      expect(find.text('星旅'), findsOneWidget);
      await tester.ensureVisible(find.text('查看名片'));
      await tester.tap(find.text('查看名片'));
      await tester.pumpAndSettle();
      expect(find.text('公開名片 peer-two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-work invite uses the existing introduction flow and then shows pending',
    (tester) async {
      final social = _Social();
      await _open(tester, const SameWorkList(), social: social);
      await tester.tap(find.text('戳友'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '我是同坑的黑帽攝影');
      await tester.tap(find.text('送出邀請'));
      await tester.pumpAndSettle();
      expect(social.invites, ['我是同坑的黑帽攝影']);
      expect(find.text('邀請已送出'), findsOneWidget);
      expect(find.text('戳友'), findsNothing);
    },
  );

  test(
    'same-work pagination deduplicates and failed loads retain the current page for retry',
    () async {
      var broken = true;
      final social = _Social()
        ..fetch = (offset) async {
          if (offset == 0) {
            return const SameWorkPage(items: [peer], nextOffset: 20);
          }
          if (broken) throw Exception('network');
          return const SameWorkPage(
            items: [
              peer,
              SameWorkUser(
                userId: '3',
                publicCode: 'three',
                nickname: '第三人',
                commonWorkCount: 1,
                commonWorks: [],
              ),
            ],
          );
        };
      final container = ProviderContainer(
        overrides: [socialRepositoryProvider.overrideWithValue(social)],
      );
      addTearDown(container.dispose);
      final listener = container.listen(sameWorkUsersProvider, (_, _) {});
      addTearDown(listener.close);
      await container.read(sameWorkUsersProvider.future);
      await expectLater(
        container.read(sameWorkUsersProvider.notifier).loadMore(),
        throwsException,
      );
      expect(
        container.read(sameWorkUsersProvider).requireValue.items.length,
        1,
      );
      broken = false;
      await container.read(sameWorkUsersProvider.notifier).loadMore();
      expect(
        container
            .read(sameWorkUsersProvider)
            .requireValue
            .items
            .map((item) => item.userId),
        ['2', '3'],
      );
      expect(social.requests, [0, 20, 20]);
    },
  );
}
