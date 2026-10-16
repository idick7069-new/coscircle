import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/features/auth/presentation/email_action_page.dart';
import 'package:coscircle/features/settings/presentation/email_verification_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class EmailRepository extends AuthRepository {
  EmailRepository()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  int requests = 0;
  String? resetValue;
  bool verified = false, fails = false;
  @override
  Future<void> forgotPassword(String email) async {
    requests++;
    if (fails) throw Exception('寄信服務暫時無法使用');
  }

  @override
  Future<void> verifyEmail(String token) async {
    requests++;
    verified = true;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    requests++;
    resetValue = password;
  }

  @override
  Future<AuthEmailStatus> emailStatus() async => AuthEmailStatus(
    email: 'owner@example.invalid',
    verified: verified,
    available: true,
  );
  @override
  Future<void> requestEmailVerification() async {
    requests++;
  }
}

void main() {
  final token = 'a' * 64;
  Future<void> open(
    WidgetTester tester,
    EmailRepository repo,
    Widget page,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening a verification link does not consume it until confirmation',
    (tester) async {
      final repo = EmailRepository();
      await open(
        tester,
        repo,
        EmailActionPage(mode: EmailActionMode.verify, token: token),
      );
      expect(repo.requests, 0);
      await tester.tap(find.text('確認驗證信箱'));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.text('信箱驗證完成。'), findsOneWidget);
    },
  );

  testWidgets('incomplete links cannot submit', (tester) async {
    final repo = EmailRepository();
    await open(
      tester,
      repo,
      const EmailActionPage(mode: EmailActionMode.reset, token: 'bad'),
    );
    expect(find.text('連結不完整或已失效，請重新申請'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('更新密碼'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(repo.requests, 0);
  });

  testWidgets(
    'password reset requires matching passwords and displays success',
    (tester) async {
      final repo = EmailRepository();
      await open(
        tester,
        repo,
        EmailActionPage(mode: EmailActionMode.reset, token: token),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'new-password');
      await tester.enterText(find.byType(TextFormField).at(1), 'different');
      await tester.tap(find.text('更新密碼'));
      await tester.pumpAndSettle();
      expect(repo.requests, 0);
      expect(find.text('兩次密碼不一致'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), 'new-password');
      await tester.tap(find.text('更新密碼'));
      await tester.pumpAndSettle();
      expect(repo.resetValue, 'new-password');
      expect(find.text('密碼已重設，請使用新密碼重新登入。'), findsOneWidget);
    },
  );

  testWidgets(
    'forgot request is generic and duplicate clicks are cooled down',
    (tester) async {
      final repo = EmailRepository();
      await open(
        tester,
        repo,
        const EmailActionPage(mode: EmailActionMode.forgot),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'owner@example.invalid',
      );
      await tester.tap(find.text('寄送重設連結'));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.textContaining('若此信箱已設定密碼登入'), findsOneWidget);
      expect(find.text('60 秒後可重寄'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed requests remain retryable and never show success', (
    tester,
  ) async {
    final repo = EmailRepository()..fails = true;
    await open(
      tester,
      repo,
      const EmailActionPage(mode: EmailActionMode.forgot),
    );
    await tester.enterText(find.byType(TextFormField), 'owner@example.invalid');
    await tester.tap(find.text('寄送重設連結'));
    await tester.pumpAndSettle();
    expect(find.text('寄信服務暫時無法使用'), findsOneWidget);
    expect(find.textContaining('申請已送出'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('寄送重設連結'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('verified settings show state and do not offer resend', (
    tester,
  ) async {
    final repo = EmailRepository()..verified = true;
    await open(tester, repo, const Scaffold(body: EmailVerificationSection()));
    expect(find.textContaining('信箱已驗證'), findsOneWidget);
    expect(find.text('寄送驗證信'), findsNothing);
  });

  testWidgets(
    'unverified settings send to their existing identity and disable duplicate requests',
    (tester) async {
      final repo = EmailRepository();
      await open(
        tester,
        repo,
        const Scaffold(body: EmailVerificationSection()),
      );
      await tester.tap(find.text('寄送驗證信'));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.text('60 秒後可重寄'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
