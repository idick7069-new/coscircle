import 'package:coscircle/core/services/apple_login_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.aboutyou.dart_packages.sign_in_with_apple',
  );
  final challenge = {'challengeId': 'a' * 64, 'nonce': 'b' * 64};
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'native Apple authorization forwards server nonce and state and returns only credentials',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'performAuthorizationRequest');
            final request = (call.arguments as List).single as Map;
            expect(request['nonce'], challenge['nonce']);
            expect(request['state'], challenge['challengeId']);
            return {
              'type': 'appleid',
              'identityToken': 'signed-token',
              'authorizationCode': 'one-time-code',
              'state': challenge['challengeId'],
            };
          });
      final result = await AppleLoginService().authorize(challenge);
      expect(result, {
        'challengeId': challenge['challengeId'],
        'identityToken': 'signed-token',
        'authorizationCode': 'one-time-code',
      });
    },
  );
  test(
    'canceling Apple authorization is a normal cancel without a login request',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'authorization-error/canceled');
          });
      expect(await AppleLoginService().authorize(challenge), isNull);
    },
  );
  test(
    'mismatched Apple state or missing identity token cannot authenticate',
    () async {
      for (final token in ['token', null]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (call) async => {
                'type': 'appleid',
                'identityToken': token,
                'authorizationCode': 'code',
                'state': token == null ? challenge['challengeId'] : 'wrong',
              },
            );
        await expectLater(
          AppleLoginService().authorize(challenge),
          throwsStateError,
        );
      }
    },
  );
  test(
    'invalid challenge and unsupported platforms never open Apple authorization',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return null;
          });
      await expectLater(
        AppleLoginService().authorize({'nonce': 'wrong'}),
        throwsStateError,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await expectLater(
        AppleLoginService().authorize(challenge),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
}
