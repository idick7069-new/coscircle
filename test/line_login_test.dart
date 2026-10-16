import 'dart:convert';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/services/line_login_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(await LineLoginService().authorize(), 'fixture-token');
      expect(calls.first.method, 'setup');
      expect(calls.first.arguments['channelId'], '2011925571');
      expect(calls.last.arguments['scopes'], ['profile']);
      await LineLoginService().authorize();
      expect(calls.where((call) => call.method == 'setup').length, 1);
    },
  );

  test('iOS uses the same SDK login flow', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await LineLoginService().authorize(), 'fixture-token');
    expect(calls.last.method, 'login');
  });

  for (final code in ['CANCEL', '3003']) {
    test('user cancellation $code returns without a login token', () async {
      cancellation = code;
      expect(await LineLoginService().authorize(), isNull);
    });
  }

  test('unsupported platforms do not invoke the native plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(LineLoginService().supported, isFalse);
    await expectLater(LineLoginService().authorize(), throwsException);
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
}
