import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../router/app_router.dart';
import '../config/app_environment.dart';
import 'local_notification_service.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  return PushNotificationService(apiClient: ref.watch(apiClientProvider));
});

class PushNotificationService {
  PushNotificationService({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _notificationTapSubscription;
  bool _initialized = false;
  String? _registeredToken;
  String? _initialTarget;
  static const _enabledKey = 'recognition_notifications_enabled';
  bool _notificationsEnabled = true;
  bool get isSupported => _isSupportedPlatform;

  Future<bool> notificationsEnabled() async {
    _notificationsEnabled =
        (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;
    if (!_notificationsEnabled ||
        !_isSupportedPlatform ||
        Firebase.apps.isEmpty) {
      return false;
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (enabled) {
      await requestPermission();
      return;
    }
    final previous = _notificationsEnabled;
    _notificationsEnabled = false;
    try {
      final token =
          _registeredToken ??
          (_isSupportedPlatform && Firebase.apps.isNotEmpty
              ? await FirebaseMessaging.instance.getToken()
              : null);
      if (token != null && token.isNotEmpty) {
        await _apiClient.deleteWithData(
          '/me/push-tokens',
          data: {'token': token},
        );
      }
      await (await SharedPreferences.getInstance()).setBool(_enabledKey, false);
      _registeredToken = null;
      await deleteDeviceToken();
    } catch (_) {
      _notificationsEnabled = previous;
      rethrow;
    }
  }

  String? get registeredToken => _registeredToken;
  String? takeInitialTarget() {
    final target = _initialTarget;
    _initialTarget = null;
    return target;
  }

  Future<void> initializeForAuthenticatedUser() async {
    if (_initialized || appDemoMode || !_isSupportedPlatform) return;
    if (Firebase.apps.isEmpty) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      _notificationsEnabled =
          (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _initialTarget = _messageTarget(initialMessage);
      }
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _syncToken(await messaging.getToken());
      }

      _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen(_syncToken);
      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
        if (!_notificationsEnabled ||
            message.data['type'] != 'recognition_request') {
          return;
        }
        final body = message.notification?.body ?? '有同好想在現場找你認親';
        unawaited(
          LocalNotificationService.instance.showRecognitionRequest(body),
        );
      });
      _notificationTapSubscription ??= FirebaseMessaging.onMessageOpenedApp
          .listen(_openMessageTarget);
    } catch (error) {
      _initialized = false;
      if (kDebugMode) debugPrint('Notification initialization failed: $error');
    }
  }

  Future<void> requestPermission() async {
    if (!_isSupportedPlatform) {
      throw Exception('此平台尚未支援認親推播通知，請使用 Android 或 iOS App');
    }
    if (Firebase.apps.isEmpty) {
      throw Exception('通知服務尚未就緒，請重新開啟 App 後再試');
    }
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw Exception('通知權限尚未開啟，請至系統設定允許通知');
    }
    await _syncToken(
      await FirebaseMessaging.instance.getToken(),
      required: true,
    );
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, true);
    _notificationsEnabled = true;
    await initializeForAuthenticatedUser();
  }

  Future<void> dispose() async {
    _initialized = false;
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _notificationTapSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _notificationTapSubscription = null;
    _initialized = false;
    _registeredToken = null;
    _initialTarget = null;
  }

  Future<void> deleteDeviceToken() async {
    if (!_isSupportedPlatform || Firebase.apps.isEmpty) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      if (kDebugMode) debugPrint('Notification token deletion failed: $error');
    }
  }

  Future<void> _syncToken(String? token, {bool required = false}) async {
    if (!_notificationsEnabled && !required) return;
    if (token == null || token.isEmpty) {
      if (required) throw Exception('無法取得通知識別碼，請稍後再試');
      return;
    }
    try {
      await _apiClient.post(
        '/me/push-tokens',
        data: {'platform': _platformName, 'token': token},
      );
      if (!_notificationsEnabled && !required) {
        await _apiClient.deleteWithData(
          '/me/push-tokens',
          data: {'token': token},
        );
        return;
      }
      _registeredToken = token;
    } catch (error) {
      if (required) rethrow;
      if (kDebugMode) debugPrint('FCM token sync failed: $error');
    }
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  String get _platformName {
    if (!kIsWeb && Platform.isIOS) return 'ios';
    return 'android';
  }

  void _openMessageTarget(RemoteMessage message) {
    final target = _messageTarget(message);
    if (target != null) appRouter.go(target);
  }

  String? _messageTarget(RemoteMessage message) {
    if (message.data['type'] != 'recognition_request') return null;
    final eventId = message.data['eventId']?.toString();
    if (eventId == null || eventId.isEmpty) return null;
    final dayIndex =
        int.tryParse(message.data['dayIndex']?.toString() ?? '') ?? 1;
    return Uri(
      path: '/current/$eventId',
      queryParameters: {'dayIndex': '$dayIndex'},
    ).toString();
  }
}
