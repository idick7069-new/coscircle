import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../api/api_client.dart';

final appleLoginServiceProvider = Provider((ref) => AppleLoginService());
final appleLoginAvailabilityProvider = FutureProvider<bool>((ref) async {
  if (!const bool.fromEnvironment('ENABLE_APPLE_LOGIN') ||
      !ref.watch(appleLoginServiceProvider).supported) {
    return false;
  }
  final response = await ref.watch(apiClientProvider).get('/auth/apple/config');
  return (response.data as Map)['enabled'] == true;
});

class AppleLoginService {
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<Map<String, String>?> authorize(Map<String, dynamic> challenge) async {
    if (!supported) throw StateError('Apple 登入目前僅支援 iOS');
    final id = challenge['challengeId'] as String?;
    final nonce = challenge['nonce'] as String?;
    if (id == null ||
        nonce == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(nonce)) {
      throw StateError('Apple 登入暫時無法使用');
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: nonce,
        state: id,
      );
      if (credential.state != id || credential.identityToken == null) {
        throw StateError('Apple 授權未完成，請重試');
      }
      return {
        'challengeId': id,
        'identityToken': credential.identityToken!,
        'authorizationCode': credential.authorizationCode,
      };
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      throw StateError('Apple 授權未完成，請稍後重試');
    }
  }
}
