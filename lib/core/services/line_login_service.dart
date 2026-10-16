import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final lineLoginServiceProvider = Provider((ref) => LineLoginService());
final lineLoginEnabledProvider = Provider(
  (ref) => const bool.fromEnvironment('ENABLE_LINE_LOGIN'),
);

class LineLoginService {
  static const channelId = String.fromEnvironment(
    'LINE_LOGIN_CHANNEL_ID',
    defaultValue: '2011925571',
  );
  static Future<void>? _setup;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<String?> authorize() async {
    if (!supported) throw Exception('LINE 登入目前僅支援 Android 與 iOS');
    try {
      await (_setup ??= LineSDK.instance.setup(channelId).catchError((
        Object error,
      ) {
        _setup = null;
        throw error;
      }));
      final result = await LineSDK.instance.login(scopes: ['profile']);
      return result.accessToken.value;
    } on PlatformException catch (error) {
      if (error.code == 'CANCEL' ||
          error.code == 'userCanceled' ||
          error.code == '3003') {
        return null;
      }
      throw Exception('LINE 授權未完成，請確認 LINE 設定或稍後重試');
    }
  }
}
