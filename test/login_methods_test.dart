import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/services/line_login_service.dart';
import 'package:coscircle/features/settings/presentation/login_methods_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class BindingRepository extends AuthRepository {
  BindingRepository({this.conflict = false})
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final bool conflict;
  final methods = ['email'];
  final requests = <Map<String, String>>[];

  @override
  Future<List<String>> loginMethods() async => [...methods];

  @override
  Future<AuthEmailStatus> emailStatus() async => const AuthEmailStatus(
    email: 'qa@example.invalid',
    verified: false,
    available: true,
  );

  @override
  Future<void> linkLine({
    required String accessToken,
    required String password,
  }) async {
    requests.add({'accessToken': accessToken, 'password': password});
    if (conflict) throw Exception('LINE 已屬於其他帳號');
    methods.add('line');
  }
}

class BindingLine extends LineLoginService {
  BindingLine({this.cancel = false});
  final bool cancel;
  @override
  bool get supported => true;
  @override
  Future<String?> authorize() async => cancel ? null : 'verified-fixture-token';
}

void main() {
  Future<void> open(
    WidgetTester tester,
    BindingRepository repo,
    BindingLine line,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          lineLoginEnabledProvider.overrideWithValue(true),
          lineLoginServiceProvider.overrideWithValue(line),
        ],
        child: const MaterialApp(home: LoginMethodsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> authorize(WidgetTester tester) async {
    await tester.tap(find.text('綁定 LINE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password');
    await tester.tap(find.text('繼續'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'binding requires password and refreshes login methods without creating a session',
    (tester) async {
      final repo = BindingRepository();
      await open(tester, repo, BindingLine());
      await authorize(tester);
      expect(repo.requests, [
        {'accessToken': 'verified-fixture-token', 'password': 'password'},
      ]);
      expect(find.text('已綁定'), findsOneWidget);
      expect(find.text('綁定 LINE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled LINE authorization does not submit a binding', (
    tester,
  ) async {
    final repo = BindingRepository();
    await open(tester, repo, BindingLine(cancel: true));
    await authorize(tester);
    expect(repo.requests, isEmpty);
    expect(repo.methods, ['email']);
  });

  testWidgets(
    'a binding conflict keeps the original login methods and shows an error',
    (tester) async {
      final repo = BindingRepository(conflict: true);
      await open(tester, repo, BindingLine());
      await authorize(tester);
      expect(repo.methods, ['email']);
      expect(find.text('LINE 已屬於其他帳號'), findsOneWidget);
      expect(find.text('未綁定'), findsOneWidget);
    },
  );
}
