import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/models/booking_visibility.dart';
import 'package:coscircle/features/profile/presentation/profile_page.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/services/push_notification_service.dart';
import 'package:coscircle/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionPush extends PushNotificationService {
  PermissionPush({this.failure})
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final Exception? failure;
  int requests = 0;
  bool enabled = false;
  @override
  bool get isSupported => true;
  @override
  Future<bool> notificationsEnabled() async => enabled;
  @override
  Future<void> setNotificationsEnabled(bool value) async {
    if (value) await requestPermission();
    enabled = value;
  }

  @override
  Future<void> requestPermission() async {
    requests++;
    if (failure != null) throw failure!;
  }
}

class SafetyProfile extends InMemoryProfileRepository {
  SafetyProfile({this.admin = false, this.visibility = 'public'});
  final bool admin;
  final String visibility;
  @override
  Future<UserProfile?> currentProfile() async => UserProfile(
    id: 'me',
    nickname: 'QA',
    isAdmin: admin,
    bookingVisibility: visibility,
  );
  @override
  Future<List<BookingFollowerGroup>> fetchBookingFollowers() async => [
    BookingFollowerGroup(
      bookingId: '1',
      eventId: '1',
      eventName: 'QA場次',
      startDate: DateTime(2026, 10, 14),
      endDate: DateTime(2026, 10, 14),
      dayIndex: 1,
      role: 'coser',
    ),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('admin still sees diagnostics entry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            SafetyProfile(admin: true),
          ),
          pushNotificationServiceProvider.overrideWithValue(PermissionPush()),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('連線狀態'), findsOneWidget);
  });

  for (final visibility in ['public', 'circle']) {
    testWidgets(
      'empty follower list does not imply $visibility booking is invisible',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileRepositoryProvider.overrideWithValue(
                SafetyProfile(visibility: visibility),
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: ProfilePage())),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.text('目前沒有追蹤者');
        await tester.scrollUntilVisible(target, 300);
        await tester.pumpAndSettle();
        expect(target, findsOneWidget);
        expect(
          find.text(visibility == 'public' ? '大家都看得到' : '僅小圈圈看得到'),
          findsWidgets,
        );
        final edit = find.text('場次安全');
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(find.text('場次預定可見範圍'), findsOneWidget);
        expect(find.text('全部人').hitTestable(), findsOneWidget);
        expect(find.text('僅小圈圈').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final denied in [false, true]) {
    testWidgets('notification tap reports ${denied ? 'denial' : 'success'}', (
      tester,
    ) async {
      final push = PermissionPush(
        failure: denied ? Exception('通知權限尚未開啟，請至系統設定允許通知') : null,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileRepositoryProvider.overrideWithValue(
              InMemoryProfileRepository(),
            ),
            pushNotificationServiceProvider.overrideWithValue(push),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(push.requests, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(denied ? '通知權限尚未開啟，請至系統設定允許通知' : '認親通知已開啟'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        !denied,
      );
      if (!denied) {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(push.enabled, false);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          false,
        );
      }
    });
  }

  test('unsupported platform must not silently report success', () async {
    final push = PushNotificationService(
      apiClient: ApiClient(baseUrl: 'https://example.invalid/api'),
    );
    await expectLater(push.requestPermission(), throwsA(isA<Exception>()));
  });

  test(
    'turning off persists across service recreation without requesting permission',
    () async {
      final push = PushNotificationService(
        apiClient: ApiClient(baseUrl: 'https://example.invalid/api'),
      );
      await push.setNotificationsEnabled(false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'recognition_notifications_enabled',
        ),
        false,
      );
      final restored = PushNotificationService(
        apiClient: ApiClient(baseUrl: 'https://example.invalid/api'),
      );
      expect(await restored.notificationsEnabled(), false);
    },
  );

  testWidgets('ordinary users cannot access connection diagnostics', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('direct-diagnostics'),
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            InMemoryProfileRepository(),
          ),
          pushNotificationServiceProvider.overrideWithValue(PermissionPush()),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('連線狀態'), findsNothing);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            InMemoryProfileRepository(),
          ),
        ],
        child: const MaterialApp(home: ConnectionStatusPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('僅管理員可使用連線診斷'), findsOneWidget);
  });
}
