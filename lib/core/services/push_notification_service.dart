import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> initializeForAuthenticatedUser() async {
    if (_initialized || appDemoMode || !_isSupportedPlatform) return;
    if (Firebase.apps.isEmpty) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await _syncToken(await messaging.getToken());

    _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen(_syncToken);
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] != 'recognition_request') return;
      final body = message.notification?.body ?? '有同好想在現場找你認親';
      unawaited(LocalNotificationService.instance.showRecognitionRequest(body));
    });
    _notificationTapSubscription ??= FirebaseMessaging.onMessageOpenedApp
        .listen(_openMessageTarget);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _openMessageTarget(initialMessage);
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _notificationTapSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _notificationTapSubscription = null;
    _initialized = false;
  }

  Future<void> _syncToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _apiClient.post(
        '/me/push-tokens',
        data: {'platform': _platformName, 'token': token},
      );
    } catch (error) {
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
    if (message.data['type'] != 'recognition_request') return;
    final eventId = message.data['eventId']?.toString();
    if (eventId == null || eventId.isEmpty) return;
    appRouter.go('/current/$eventId');
  }
}
