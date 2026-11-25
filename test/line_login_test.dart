import 'package:coscircle/core/services/token_store.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/services/line_login_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _WebLinkAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        status == 200
            ? (options.path.endsWith('/start')
                  ? {'url': 'https://access.line.me/oauth2/v2.1/authorize'}
                  : {'linked': true})
            : {'error': 'line_identity_already_linked'},
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.linecorp/flutter_line_sdk');
  final calls = <MethodCall>[];
  String? cancellation;
  setUp(() {
    calls.clear();
    cancellation = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'setup') return null;
          if (cancellation != null) {
            throw PlatformException(code: cancellation!);
          }
          return jsonEncode({
            'accessToken': {'access_token': 'fixture-token'},
          });
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android SDK uses the configured channel and only profile scope',
    () async {
      expect(
        await LineLoginService(
          channelIdLoader: () async => '1234567890',
        ).authorize(),
        'fixture-token',
      );
      expect(calls.first.method, 'setup');
      expect(calls.first.arguments['channelId'], '1234567890');
      expect(calls.last.arguments['scopes'], ['profile']);
      await LineLoginService(
        channelIdLoader: () async => '1234567890',
      ).authorize();
      expect(calls.where((call) => call.method == 'setup').length, 1);
    },
  );

  test('iOS uses the same SDK login flow', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      await LineLoginService(
        channelIdLoader: () async => '1234567890',
      ).authorize(),
      'fixture-token',
    );
    expect(calls.last.method, 'login');
  });

  for (final code in ['CANCEL', '3003']) {
    test('user cancellation $code returns without a login token', () async {
      cancellation = code;
      expect(
        await LineLoginService(
          channelIdLoader: () async => '1234567890',
        ).authorize(),
        isNull,
      );
    });
  }

  test('unsupported platforms do not invoke the native plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      LineLoginService(channelIdLoader: () async => '1234567890').supported,
      isFalse,
    );
    await expectLater(
      LineLoginService(channelIdLoader: () async => '1234567890').authorize(),
      throwsException,
    );
    expect(calls, isEmpty);
  });

  test('LINE credentials are never sent to an HTTP API', () async {
    final auth = AuthRepository(
      apiClient: ApiClient(baseUrl: 'http://example.invalid/api'),
    );
    await expectLater(
      auth.socialLogin(
        provider: SocialLoginProvider.line,
        accessToken: 'fixture-token',
      ),
      throwsA(predicate((error) => '$error'.contains('HTTPS'))),
    );
  });
  test(
    'Web link endpoints use the current session and never replace its token',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'original-session',
      });
      final adapter = _WebLinkAdapter();
      final auth = AuthRepository(
        apiClient: ApiClient(
          baseUrl: 'https://coscircle.app/api',
          adapter: adapter,
        ),
      );
      expect(
        await auth.startLineWebLink(),
        startsWith('https://access.line.me/'),
      );
      await auth.completeLineWebLink(password: 'original-password');
      expect(adapter.requests.map((r) => r.path), [
        '/me/auth-identities/line/web/start',
        '/me/auth-identities/line/web/complete',
      ]);
      expect(
        adapter.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer original-session',
        ),
        isTrue,
      );
      expect(adapter.requests.last.data, {'password': 'original-password'});
      expect(await TokenStore().read(), 'original-session');
    },
  );
  test(
    'Web link conflicts propagate without changing the original session',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'original-session',
      });
      final adapter = _WebLinkAdapter()..status = 409;
      final auth = AuthRepository(
        apiClient: ApiClient(
          baseUrl: 'https://coscircle.app/api',
          adapter: adapter,
        ),
      );
      await expectLater(
        auth.completeLineWebLink(password: 'password'),
        throwsA(isA<DioException>()),
      );
      expect(await TokenStore().read(), 'original-session');
    },
  );
}
