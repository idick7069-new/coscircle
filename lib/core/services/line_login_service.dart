import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';

final lineLoginServiceProvider = Provider(
  (ref) => LineLoginService(
    channelIdLoader: () async {
      final response = await ref
          .read(apiClientProvider)
          .get('/auth/line/config');
      final config = response.data as Map;
      if (config['enabled'] != true || config['channelId'] is! String) {
        throw StateError('LINE 登入尚未開放');
      }
      return config['channelId'] as String;
    },
  ),
);
final lineLoginEnabledProvider = Provider(
  (ref) => const bool.fromEnvironment('ENABLE_LINE_LOGIN'),
);

class LineLoginService {
  static const channelId = String.fromEnvironment(
    'LINE_LOGIN_CHANNEL_ID',
    defaultValue: '',
  );
  LineLoginService({this.channelIdLoader});
  final Future<String> Function()? channelIdLoader;
  static Future<void>? _setup;
  static String? _setupChannelId;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<String?> authorize() async {
    if (!supported) throw Exception('LINE 登入目前僅支援 Android 與 iOS');
    try {
      final id = await (channelIdLoader?.call() ?? Future.value(channelId));
      if (!RegExp(r'^\d+$').hasMatch(id)) throw StateError('LINE 登入尚未設定');
      if (_setupChannelId != id) {
        _setup = null;
        _setupChannelId = id;
      }
      await (_setup ??= LineSDK.instance.setup(id).catchError((Object error) {
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

final lineLoginAvailabilityProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(lineLoginEnabledProvider)) return false;
  final response = await ref.watch(apiClientProvider).get('/auth/line/config');
  final config = response.data as Map;
  return config[kIsWeb ? 'webEnabled' : 'enabled'] == true;
});
