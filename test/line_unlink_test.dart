import 'package:coscircle/core/services/token_store.dart';
import 'dart:convert';
import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/services/line_login_service.dart';
import 'package:coscircle/features/settings/presentation/login_methods_page.dart';
import 'package:coscircle/features/settings/presentation/email_verification_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        status == 200
            ? {'unlinked': true}
            : {'error': 'reauthentication_required'},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Auth extends AuthRepository {
  _Auth({this.methods = const ['email', 'line']})
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  List<String> methods;
  final passwords = <String>[];
  bool fail = false;
  @override
  Future<List<String>> loginMethods() async => methods;
  @override
  Future<void> unlinkLine({required String password}) async {
    passwords.add(password);
    if (fail) throw Exception('請輸入目前帳號正確的 Email 登入密碼');
    methods = ['email'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> open(WidgetTester tester, _Auth auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          lineLoginAvailabilityProvider.overrideWith((ref) async => false),
          authEmailStatusProvider.overrideWith(
            (ref) async => const AuthEmailStatus(
              email: 'qa@example.invalid',
              verified: true,
              available: true,
            ),
          ),
        ],
        child: const MaterialApp(home: LoginMethodsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('unlink uses DELETE with current session and never clears it', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'original-session'});
    final adapter = _Adapter();
    final auth = AuthRepository(
      apiClient: ApiClient(
        baseUrl: 'https://coscircle.app/api',
        adapter: adapter,
      ),
    );
    await auth.unlinkLine(password: 'correct');
    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path, '/me/auth-identities/line');
    expect(adapter.requests.single.data, {'password': 'correct'});
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer original-session',
    );
    expect(await TokenStore().read(), 'original-session');
    adapter.status = 403;
    await expectLater(
      auth.unlinkLine(password: 'wrong'),
      throwsA(isA<DioException>()),
    );
    expect(await TokenStore().read(), 'original-session');
  });
  test('unlink refuses HTTP before sending any password', () async {
    final adapter = _Adapter();
    final auth = AuthRepository(
      apiClient: ApiClient(
        baseUrl: 'http://example.invalid/api',
        adapter: adapter,
      ),
    );
    await expectLater(auth.unlinkLine(password: 'secret'), throwsException);
    expect(adapter.requests, isEmpty);
  });
  testWidgets('cancelled confirmation does not unlink', (tester) async {
    final auth = _Auth();
    await open(tester, auth);
    await tester.tap(find.text('解綁 LINE'));
    await tester.pumpAndSettle();
    expect(find.text('確認解綁 LINE'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(auth.passwords, isEmpty);
  });
  testWidgets('confirmed unlink refreshes the visible login methods', (
    tester,
  ) async {
    final auth = _Auth();
    await open(tester, auth);
    await tester.tap(find.text('解綁 LINE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'correct');
    await tester.tap(find.text('確認解綁'));
    await tester.pumpAndSettle();
    expect(auth.passwords, ['correct']);
    expect(find.text('未綁定'), findsOneWidget);
    expect(find.text('解綁 LINE'), findsNothing);
    expect(find.text('Email／密碼'), findsOneWidget);
  });
  testWidgets('wrong password displays an error and leaves LINE bound', (
    tester,
  ) async {
    final auth = _Auth()..fail = true;
    await open(tester, auth);
    await tester.tap(find.text('解綁 LINE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('確認解綁'));
    await tester.pumpAndSettle();
    expect(find.text('已綁定'), findsOneWidget);
    expect(find.text('請輸入目前帳號正確的 Email 登入密碼'), findsOneWidget);
  });
  testWidgets('LINE-only account cannot open unlink confirmation', (
    tester,
  ) async {
    final auth = _Auth(methods: ['line']);
    await open(tester, auth);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('解綁 LINE'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('目前只有 LINE 登入，需先有可用的 Email／密碼才能解綁。'), findsOneWidget);
    expect(auth.passwords, isEmpty);
  });
}
