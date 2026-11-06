import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/admin_stats.dart';
import 'package:coscircle/core/repositories/account_safety_repository.dart';
import 'package:coscircle/core/services/line_login_service.dart';
import 'package:coscircle/core/services/push_notification_service.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/features/safety/presentation/delete_account_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Push extends PushNotificationService {
  _Push(ApiClient api) : super(apiClient: api);
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

final _deleteButton = find.byWidgetPredicate(
  (widget) => widget is FilledButton,
);

void main() {
  setUpAll(() async {
    for (final entry in {
      'Roboto': const String.fromEnvironment('QA_LATIN_FONT'),
      'Noto Sans TC': const String.fromEnvironment('QA_CJK_FONT'),
    }.entries) {
      if (entry.value.isNotEmpty) {
        await (FontLoader(entry.key)..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            ))
            .load();
      }
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'A'}));

  test('admin cleanup statistics remain compatible with an older response', () {
    expect(AdminStats.fromJson({}).uploadCleanup, 0);
    final stats = AdminStats.fromJson({'uploadCleanup': 2, 'legacyUploadReview': '3'});
    expect(stats.uploadCleanup, 2);
    expect(stats.legacyUploadReview, 3);
  });

  test('deletion request stays bound to original account and proof', () async {
    final adapter = _Adapter((_) => _json({}, 204));
    final api = ApiClient(baseUrl: 'https://api.invalid/api', adapter: adapter);
    api.setAuthToken('A');
    final session = api.captureSession();
    await AccountSafetyRepository(
      api,
    ).deleteAccount(session: session, password: 'secret-password');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer A');
    expect(adapter.requests.single.data, {
      'confirmation': 'DELETE',
      'password': 'secret-password',
    });
    api.setAuthToken('B');
    await expectLater(
      AccountSafetyRepository(
        api,
      ).deleteAccount(session: session, password: 'secret-password'),
      throwsStateError,
    );
    expect(adapter.requests.length, 1);
    expect(await api.restoreAuthToken(), 'B');
  });

  test('late deletion response cannot clear a replacement account', () async {
    final pending = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = _Adapter((_) {
      started.complete();
      return pending.future;
    });
    final api = ApiClient(baseUrl: 'https://api.invalid/api', adapter: adapter)
      ..setAuthToken('A');
    final session = api.captureSession();
    final deleting = AccountSafetyRepository(
      api,
    ).deleteAccount(session: session, password: 'secret-password');
    final result = expectLater(
      deleting,
      throwsA(anyOf(isA<DioException>(), isA<StateError>())),
    );
    await started.future;
    await api.persistAuthToken('B');
    pending.complete(_json({}, 204));
    await result;
    expect(await api.restoreAuthToken(), 'B');
    expect(
      (await SharedPreferences.getInstance()).getString('auth_token'),
      'B',
    );
  });

  Future<(ApiClient, _Adapter, _Push)> open(
    WidgetTester tester, {
    int deleteStatus = 204,
    bool restoreOnly = false,
  }) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = _Adapter(
      (request) => request.path.endsWith('auth-identities')
          ? _json([
              {'provider': 'email'},
            ])
          : request.method == 'GET' && request.path == '/me'
          ? _json({'nickname': 'QA', 'email': 'qa@example.invalid'})
          : _json(
              deleteStatus == 204 ? {} : {'error': 'reauthentication_required'},
              deleteStatus,
            ),
    );
    final api = ApiClient(baseUrl: 'https://api.invalid/api', adapter: adapter);
    if (!restoreOnly) api.setAuthToken('A');
    final push = _Push(api);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DeleteAccountPage()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('登入完成清理')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          lineLoginEnabledProvider.overrideWithValue(false),
          pushNotificationServiceProvider.overrideWithValue(push),
        ],
        child: RepaintBoundary(
          key: const ValueKey('account-safety-preview'),
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (api, adapter, push);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(_field('目前帳號的登入密碼'));
    await tester.enterText(_field('目前帳號的登入密碼'), 'secret-password');
    await tester.ensureVisible(_field('輸入 DELETE 確認刪除'));
    await tester.enterText(_field('輸入 DELETE 確認刪除'), 'DELETE');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'requires unchecked confirmation and cleans session only after success',
    (tester) async {
      final (api, adapter, push) = await open(tester);
      if (const bool.fromEnvironment('QA_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('account-safety-preview')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/ui-preview').create(recursive: true);
            await File(
              'build/ui-preview/delete-account.png',
            ).writeAsBytes(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      expect(tester.widget<FilledButton>(_deleteButton).onPressed, isNull);
      expect(adapter.requests.length, 2);
      await confirm(tester);
      await tester.tap(find.text('永久刪除帳號'));
      await tester.pumpAndSettle();
      expect(find.text('登入完成清理'), findsOneWidget);
      expect(push.disposals, 1);
      expect(await api.restoreAuthToken(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wrong password leaves account signed in and permits retry', (
    tester,
  ) async {
    final (api, _, push) = await open(tester, deleteStatus: 403);
    await confirm(tester);
    await tester.tap(find.text('永久刪除帳號'));
    await tester.pumpAndSettle();
    expect(find.text('請輸入目前帳號正確的 Email 登入密碼'), findsOneWidget);
    expect(await api.restoreAuthToken(), 'A');
    expect(push.disposals, 0);
    expect(tester.widget<FilledButton>(_deleteButton).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct entry restores stored session before showing the account',
    (tester) async {
      final (api, adapter, _) = await open(tester, restoreOnly: true);
      expect(find.text('刪除帳號：QA（qa@example.invalid）'), findsOneWidget);
      expect(await api.restoreAuthToken(), 'A');
      expect(adapter.requests.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
