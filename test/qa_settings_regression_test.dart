import 'dart:async';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/submission_repository.dart';
import 'package:coscircle/core/services/line_login_service.dart';
import 'package:coscircle/core/services/push_notification_service.dart';
import 'package:coscircle/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthRepository {
  _Auth() : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  @override
  Future<List<String>> loginMethods() async => ['email'];
  @override
  Future<AuthEmailStatus> emailStatus() async => const AuthEmailStatus(
    email: 'qa@example.invalid',
    verified: false,
    available: true,
  );
}

class _Submissions extends SubmissionRepository {
  _Submissions()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final pending = Completer<void>();
  var sent = 0;
  @override
  Future<void> submitEvent({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String venue,
    required String detailedAddress,
    required String description,
  }) async {
    sent++;
    await pending.future;
  }
}

class _PushState extends PushNotificationService {
  _PushState()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final changes = <bool>[];
  var disposals = 0;
  var deletions = 0;
  @override
  bool get isSupported => true;
  @override
  Future<bool> notificationsEnabled() async => activeNotifications.value;
  @override
  Future<void> setNotificationsEnabled(bool enabled) async {
    changes.add(enabled);
    activeNotifications.value = enabled;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    activeNotifications.value = false;
  }

  @override
  Future<void> deleteDeviceToken() async {
    deletions++;
  }
}

class _PendingLogout extends _Auth {
  final pending = Completer<bool>();
  var calls = 0;
  @override
  Future<bool> logout({String? pushToken}) async {
    calls++;
    return pending.future;
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(
    WidgetTester tester, {
    _Submissions? submissions,
    _PushState? push,
    AuthRepository? auth,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lineLoginEnabledProvider.overrideWithValue(false),
          authRepositoryProvider.overrideWithValue(auth ?? _Auth()),
          profileRepositoryProvider.overrideWithValue(
            InMemoryProfileRepository(),
          ),
          if (submissions != null)
            submissionRepositoryProvider.overrideWithValue(submissions),
          if (push != null)
            pushNotificationServiceProvider.overrideWithValue(push),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Q05 email verification remains accessible with LINE disabled', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.text('登入方式'));
    await tester.tap(find.text('登入方式'));
    await tester.pumpAndSettle();
    expect(find.textContaining('qa@example.invalid'), findsOneWidget);
    expect(find.text('綁定 LINE'), findsNothing);
    expect(find.text('寄送驗證信'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Q21 successful background registration updates the switch and permits turning off',
    (tester) async {
      final push = _PushState();
      await open(tester, push: push);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      push.activeNotifications.value = true;
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(push.changes, [false]);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.pumpWidget(const SizedBox());
      push.activeNotifications.value = true;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Q01 Q21 delayed logout cannot clean up replacement account notifications',
    (tester) async {
      final push = _PushState();
      final auth = _PendingLogout();
      addTearDown(() {
        if (!auth.pending.isCompleted) auth.pending.complete(false);
      });
      await open(tester, push: push, auth: auth);
      await tester.ensureVisible(find.text('登出'));
      await tester.tap(find.text('登出'));
      await tester.pump();
      expect(auth.calls, 1);
      expect(push.disposals, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
      container.read(apiClientProvider).setAuthToken('replacement');
      push.activeNotifications.value = true;
      auth.pending.complete(false);
      await tester.pumpAndSettle();
      expect(push.disposals, 1);
      expect(push.deletions, 0);
      expect(push.activeNotifications.value, true);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Q11 dismissal protects submission draft and explicit discard closes it',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('投稿活動'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('活動名稱'), '未送出活動');
      await tester.pump();
      await tester.drag(find.byType(BottomSheet), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(_field('活動名稱'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(_field('活動名稱'), findsOneWidget);
      await tester.tap(find.byTooltip('關閉投稿'));
      await tester.pumpAndSettle();
      expect(find.text('放棄這次投稿？'), findsOneWidget);
      await tester.tap(find.text('繼續編輯'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('活動名稱')).controller!.text,
        '未送出活動',
      );
      await tester.tap(find.byTooltip('關閉投稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放棄'));
      await tester.pumpAndSettle();
      expect(_field('活動名稱'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Q11 pending submission cannot dismiss or send twice and shows completion',
    (tester) async {
      final repository = _Submissions();
      addTearDown(() {
        if (!repository.pending.isCompleted) repository.pending.complete();
      });
      await open(tester, submissions: repository);
      await tester.tap(find.text('投稿活動'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('活動名稱'), '投稿測試');
      await tester.enterText(_field('活動地點'), '測試會場');
      final submit = find.text('送出審核');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(repository.sent, 1);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '關閉投稿',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_field('活動名稱'), findsOneWidget);
      expect(find.text('放棄這次投稿？'), findsNothing);
      repository.pending.complete();
      await tester.pumpAndSettle();
      expect(_field('活動名稱'), findsNothing);
      expect(find.text('已送出投稿，等待管理者審核'), findsOneWidget);
      expect(repository.sent, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
