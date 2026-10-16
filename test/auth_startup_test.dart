import 'dart:async';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/services/push_notification_service.dart';
import 'package:coscircle/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class StartupAuth extends AuthRepository {
  StartupAuth()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  Completer<String?> token = Completer<String?>();
  @override
  Future<String?> restoreToken() => token.future;
}

class StartupProfile extends InMemoryProfileRepository {
  Completer<UserProfile?> profile = Completer<UserProfile?>();
  @override
  Future<UserProfile?> currentProfile() => profile.future;
}

class StartupPush extends PushNotificationService {
  StartupPush()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  @override
  Future<void> initializeForAuthenticatedUser() async {}
}

void main() {
  Future<void> open(
    WidgetTester tester,
    StartupAuth auth,
    StartupProfile profile, {
    String initial = '/login',
    Completer<void>? redirectDelay,
  }) async {
    final router = GoRouter(
      initialLocation: initial,
      redirect: (context, state) async {
        if (state.uri.path == '/') await redirectDelay?.future;
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('主頁')),
        ),
        GoRoute(
          path: '/events/:id',
          builder: (_, _) => const Scaffold(body: Text('目標活動')),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Scaffold(body: Text('基本資料設定')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profile),
          pushNotificationServiceProvider.overrideWithValue(StartupPush()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'no login form is rendered while token, profile or router checks are pending',
    (tester) async {
      final auth = StartupAuth();
      final profile = StartupProfile();
      final redirectDelay = Completer<void>();
      await open(tester, auth, profile, redirectDelay: redirectDelay);
      expect(find.text('正在確認登入狀態'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      auth.token.complete('valid');
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      profile.profile.complete(
        const UserProfile(id: '1', nickname: 'user', onboardingCompleted: true),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('正在確認登入狀態'), findsOneWidget);
      redirectDelay.complete();
      await tester.pumpAndSettle();
      expect(find.text('主頁'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'missing or expired session shows the login form only after checking',
    (tester) async {
      final auth = StartupAuth();
      await open(tester, auth, StartupProfile());
      expect(find.byType(TextField), findsNothing);
      auth.token.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('正在確認登入狀態'), findsNothing);
    },
  );

  testWidgets(
    'network failure stays on retry screen and retry can restore the session',
    (tester) async {
      final auth = StartupAuth();
      final profile = StartupProfile();
      await open(tester, auth, profile);
      auth.token.completeError(TimeoutException('network'));
      await tester.pumpAndSettle();
      expect(find.text('重新連線'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      auth.token = Completer<String?>();
      await tester.tap(find.text('重新連線'));
      await tester.pump();
      expect(find.text('正在確認登入狀態'), findsOneWidget);
      auth.token.complete('valid');
      profile.profile.complete(
        const UserProfile(id: '1', nickname: 'user', onboardingCompleted: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('主頁'), findsOneWidget);
    },
  );

  testWidgets(
    'network failure allows explicitly switching to another account',
    (tester) async {
      final auth = StartupAuth();
      await open(tester, auth, StartupProfile());
      auth.token.completeError(TimeoutException('network'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用其他帳號登入'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
    },
  );

  testWidgets(
    'unfinished profile goes directly to onboarding without the login form',
    (tester) async {
      final auth = StartupAuth();
      final profile = StartupProfile();
      await open(tester, auth, profile);
      auth.token.complete('valid');
      profile.profile.complete(
        const UserProfile(
          id: '1',
          nickname: 'user',
          onboardingCompleted: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('基本資料設定'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('restored session preserves the requested destination', (
    tester,
  ) async {
    final auth = StartupAuth();
    final profile = StartupProfile();
    await open(tester, auth, profile, initial: '/login?next=%2Fevents%2F10');
    auth.token.complete('valid');
    profile.profile.complete(
      const UserProfile(id: '1', nickname: 'user', onboardingCompleted: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('目標活動'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
