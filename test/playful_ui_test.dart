import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscircle/core/models/friendship.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/models/same_work_user.dart';
import 'package:coscircle/core/models/work.dart';
import 'package:coscircle/core/providers/theme_mode_provider.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/features/auth/presentation/login_page.dart';
import 'package:coscircle/features/auth/presentation/email_action_page.dart';
import 'package:coscircle/features/events/presentation/my_events_page.dart';
import 'package:coscircle/features/events/presentation/event_booking_share_page.dart';
import 'package:coscircle/features/profile/presentation/public_profile_page.dart';
import 'package:coscircle/features/profile/presentation/onboarding_profile_page.dart';
import 'package:coscircle/features/social/presentation/join_circle_page.dart';
import 'package:coscircle/features/events/presentation/event_detail_page.dart';
import 'package:coscircle/features/events/presentation/event_list_page.dart';
import 'package:coscircle/features/profile/presentation/profile_page.dart';
import 'package:coscircle/features/settings/presentation/settings_page.dart';
import 'package:coscircle/features/settings/presentation/theme_settings_page.dart';
import 'package:coscircle/features/social/presentation/social_page.dart';
import 'package:coscircle/features/social/presentation/same_work_list.dart';
import 'package:coscircle/shared/widgets/cos_illustration.dart';
import 'package:coscircle/shared/widgets/cos_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'alpha_regression_test.dart' as qa;

class _Social extends qa.FixtureSocial {
  @override
  Future<List<Friendship>> fetchFriendships() async => [];
  @override
  Future<SameWorkPage> fetchSameWorkUsers({int offset = 0}) async =>
      const SameWorkPage(
        items: [
          SameWorkUser(
            userId: '2',
            publicCode: 'qa-peer',
            nickname: '小光攝影',
            commonWorkCount: 2,
            commonWorks: [
              WorkTag(id: '100', name: '星旅'),
              WorkTag(id: '200', name: '原神'),
            ],
          ),
        ],
      );
}

class _Profile extends qa.FixtureProfile {
  @override
  Future<UserProfile?> fetchProfile(String publicCode) async => profile;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_TW');
    await (FontLoader('FusionPixel')..addFont(
          rootBundle.load(
            'assets/fonts/fusion-pixel-12px-proportional-zh_hant.ttf',
          ),
        ))
        .load();
    final latinPath = const String.fromEnvironment('QA_LATIN_FONT');
    if (latinPath.isNotEmpty) {
      await (FontLoader('Roboto')..addFont(
            Future.value(
              ByteData.sublistView(await File(latinPath).readAsBytes()),
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final path = const String.fromEnvironment('QA_CJK_FONT');
    if (path.isNotEmpty) {
      await (FontLoader('Noto Sans TC')..addFont(
            Future.value(ByteData.sublistView(await File(path).readAsBytes())),
          ))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'new installs use dark pixel theme; stored enum choices remain compatible',
    () {
      expect(CosCircleThemeMode.fromStorage(null), CosCircleThemeMode.neonDark);
      expect(
        CosCircleThemeMode.fromStorage('neon_dark'),
        CosCircleThemeMode.neonDark,
      );
      expect(
        CosCircleThemeMode.fromStorage('morandi_light'),
        CosCircleThemeMode.morandiLight,
      );
      expect(AppTheme.morandi.colorScheme.primary, AppTheme.lavender);
      expect(AppTheme.morandi.colorScheme.secondary, const Color(0xffa8d8ff));
      for (final theme in [AppTheme.light, AppTheme.morandi, AppTheme.dark]) {
        expect(theme.textTheme.bodyMedium?.letterSpacing, 0);
        expect(theme.textTheme.headlineSmall?.letterSpacing, 0);
        final scheme = theme.colorScheme;
        for (final pair in [
          (scheme.primary, scheme.onPrimary),
          (scheme.secondary, scheme.onSecondary),
        ]) {
          final a = pair.$1.computeLuminance();
          final b = pair.$2.computeLuminance();
          final ratio = a > b
              ? (a + 0.05) / (b + 0.05)
              : (b + 0.05) / (a + 0.05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
    },
  );

  testWidgets('theme selection updates page surfaces and action colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(appThemeModeProvider);
            return MaterialApp(
              theme: switch (mode) {
                CosCircleThemeMode.neonDark => AppTheme.dark,
                CosCircleThemeMode.morandiLight => AppTheme.morandi,
                CosCircleThemeMode.whitePixel => AppTheme.whitePixel,
              },
              home: const ThemeSettingsPage(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    ThemeData currentTheme() =>
        Theme.of(tester.element(find.byType(ThemeSettingsPage)));
    final before = currentTheme();
    await tester.ensureVisible(find.text('冷調微光'));
    await tester.tap(find.text('冷調微光'));
    await tester.pumpAndSettle();
    final after = currentTheme();
    expect(
      after.scaffoldBackgroundColor,
      isNot(before.scaffoldBackgroundColor),
    );
    expect(after.colorScheme.primary, isNot(before.colorScheme.primary));
    expect(after.colorScheme.secondary, isNot(before.colorScheme.secondary));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('coscircle_pixel_theme_mode_v1'), 'morandi_light');
    await tester.ensureVisible(find.text('白晝像素'));
    await tester.tap(find.text('白晝像素'));
    await tester.pumpAndSettle();
    expect(currentTheme().scaffoldBackgroundColor, Colors.white);
    expect(currentTheme().brightness, Brightness.light);
    expect(prefs.getString('coscircle_pixel_theme_mode_v1'), 'white_pixel');
    expect(
      CosCircleThemeMode.fromStorage('white_pixel'),
      CosCircleThemeMode.whitePixel,
    );
    await tester.ensureVisible(find.text('午夜像素'));
    await tester.tap(find.text('午夜像素'));
    await tester.pumpAndSettle();
    expect(currentTheme().colorScheme.primary, before.colorScheme.primary);
    expect(
      currentTheme().scaffoldBackgroundColor,
      before.scaffoldBackgroundColor,
    );
    expect(tester.takeException(), isNull);
  });

  final pages = <String, Widget Function()>{
    'profile': () => const ProfilePage(),
    'events': () => EventListPage(onOpenCurrentEvent: (_) {}),
    'detail': () => const EventDetailPage(eventId: 'qa'),
    'social': () => const SocialPage(),
    'same-works': () => const SameWorkList(),
    'settings': () => const SettingsPage(),
    'theme': () => const ThemeSettingsPage(),
    'login': () => const LoginPage(),
    'public-profile': () => const PublicProfilePage(publicCode: 'qa-profile'),
    'onboarding': () => const OnboardingProfilePage(),
    'my-events': () => const MyEventsPage(),
    'share': () => EventBookingSharePage(
      event: qa.sampleEvent(),
      bookings: [qa.sampleParticipant],
    ),
    'join-circle': () => const JoinCirclePage(inviteCode: 'CIRCLE123'),
    'email': () => const EmailActionPage(mode: EmailActionMode.forgot),
  };
  for (final dark in [false, true]) {
    for (final entry in pages.entries) {
      testWidgets('playful ${entry.key} dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final profile = _Profile()
          ..profile = const UserProfile(
            id: 'me',
            publicCode: 'qa-profile',
            nickname: '小葵 Aoi',
            bio: '喜歡出角，也喜歡記錄同好的笑容。',
            profileRoles: ['coser', 'photographer'],
            regions: ['北部'],
          );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileRepositoryProvider.overrideWithValue(profile),
              eventRepositoryProvider.overrideWithValue(qa.FixtureEvents()),
              socialRepositoryProvider.overrideWithValue(_Social()),
            ],
            child: RepaintBoundary(
              key: const ValueKey('playful-preview'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? AppTheme.dark : AppTheme.light,
                locale: const Locale('zh', 'TW'),
                supportedLocales: const [Locale('zh', 'TW')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                ),
                home: Scaffold(body: entry.value()),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          await precacheImage(
            const AssetImage('assets/illustrations/meet-your-circle.png'),
            context,
          );
          if (!context.mounted) return;
          await precacheImage(
            const AssetImage('assets/illustrations/next-event.png'),
            context,
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('QA_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('playful-preview')),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('build/ui-preview');
              await folder.create(recursive: true);
              await File(
                '${folder.path}/${entry.key}-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        if (entry.key == 'profile') {
          await tester.tap(find.text('我的 QRCode'));
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('illustration assets render and reduced motion is immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: CosReveal(child: CosIllustration())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(SlideTransition), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
