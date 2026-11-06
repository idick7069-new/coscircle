import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

String? currentEventNotificationTarget(Map<String, dynamic> data) {
  if (!const {
    'recognition_request',
    'recognition_response',
    'meetup_created',
  }.contains(data['type'])) {
    return null;
  }
  final eventId = data['eventId']?.toString();
  final dayIndex = int.tryParse(data['dayIndex']?.toString() ?? '');
  if (eventId == null || eventId.isEmpty || dayIndex == null || dayIndex < 1) {
    return null;
  }
  return Uri(
    pathSegments: ['', 'current', eventId],
    queryParameters: {'dayIndex': '$dayIndex'},
  ).toString();
}

class PushTokenRegistration {
  PushTokenRegistration(this._apiClient);
  final ApiClient _apiClient;
  String? _registeredToken;
  ApiSession? _session;
  String? get registeredToken =>
      _session?.isActive == true ? _registeredToken : null;

  void clear() {
    _registeredToken = null;
    _session = null;
  }

  Future<void> sync(String token, String platform, ApiSession session) async {
    session.checkActive();
    if (identical(_session, session) && registeredToken == token) return;
    await _apiClient.post(
      '/me/push-tokens',
      data: {'platform': platform, 'token': token},
      session: session,
    );
    session.checkActive();
    _session = session;
    _registeredToken = token;
  }
}

class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService({required ApiClient apiClient})
    : _apiClient = apiClient,
      _registration = PushTokenRegistration(apiClient),
      _messagingOverride = null;

  @visibleForTesting
  PushNotificationService.forTesting({
    required ApiClient apiClient,
    required FirebaseMessaging messaging,
  }) : _apiClient = apiClient,
       _registration = PushTokenRegistration(apiClient),
       _messagingOverride = messaging;

  final ApiClient _apiClient;
  final FirebaseMessaging? _messagingOverride;
  FirebaseMessaging get _messaging =>
      _messagingOverride ?? FirebaseMessaging.instance;
  bool get _messagingReady =>
      _messagingOverride != null || Firebase.apps.isNotEmpty;

  /// Actual registration state, including automatic retries. Listeners remove
  /// themselves; dispose resets the value but keeps this notifier reusable.
  final activeNotifications = ValueNotifier<bool>(false);
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _notificationTapSubscription;
  bool _initialized = false;
  final PushTokenRegistration _registration;
  Future<void>? _initializing;
  ApiSession? _session;
  Timer? _retryTimer;
  bool _initialMessageRead = false;
  String? _initialTarget;
  static const _enabledKey = 'recognition_notifications_enabled';
  bool _notificationsEnabled = true;
  bool get isSupported => _isSupportedPlatform;

  Future<bool> notificationsEnabled() async {
    _notificationsEnabled =
        (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;
    if (!_notificationsEnabled || !_isSupportedPlatform || !_messagingReady) {
      activeNotifications.value = false;
      return false;
    }
    final session = _authenticatedSession();
    await initializeForAuthenticatedUser();
    session.checkActive();
    final settings = await _messaging.getNotificationSettings();
    session.checkActive();
    activeNotifications.value =
        _notificationsEnabled &&
        _registration.registeredToken != null &&
        (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional);
    return activeNotifications.value;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (enabled) {
      await requestPermission();
      return;
    }
    final previous = _notificationsEnabled;
    _notificationsEnabled = false;
    activeNotifications.value = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    ApiSession? session;
    try {
      session = _isSupportedPlatform && _messagingReady
          ? _authenticatedSession()
          : null;
      final token =
          _registration.registeredToken ??
          (_isSupportedPlatform && _messagingReady
              ? await _messaging.getToken()
              : null);
      session?.checkActive();
      if (token != null && token.isNotEmpty) {
        await _apiClient.deleteWithData(
          '/me/push-tokens',
          data: {'token': token},
          session: session,
        );
      }
      final preferences = await SharedPreferences.getInstance();
      session?.checkActive();
      await preferences.setBool(_enabledKey, false);
      session?.checkActive();
      _registration.clear();
      await deleteDeviceToken();
    } catch (_) {
      if (session == null || session.isActive) {
        _notificationsEnabled = previous;
        activeNotifications.value = previous && registeredToken != null;
      }
      rethrow;
    }
  }

  String? get registeredToken => _registration.registeredToken;
  String? takeInitialTarget() {
    final target =
        _initialTarget ?? LocalNotificationService.instance.takeInitialTarget();
    _initialTarget = null;
    return _session?.isActive == true && _notificationsEnabled ? target : null;
  }

  Future<void> initializeForAuthenticatedUser() {
    if (appDemoMode || !_isSupportedPlatform || !_messagingReady) {
      return Future.value();
    }
    final ApiSession session;
    try {
      session = _authenticatedSession();
    } on StateError {
      activeNotifications.value = false;
      return Future.value();
    }
    final pending = _initializing;
    if (pending != null) return pending;
    final operation = _initialize(session);
    _initializing = operation;
    return operation.whenComplete(() {
      if (identical(_initializing, operation)) _initializing = null;
    });
  }

  ApiSession _authenticatedSession() {
    if (_session?.isActive != true) {
      activeNotifications.value = false;
      _initialTarget = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      final tokenSubscription = _tokenRefreshSubscription;
      final foregroundSubscription = _foregroundSubscription;
      final tapSubscription = _notificationTapSubscription;
      _tokenRefreshSubscription = null;
      _foregroundSubscription = null;
      _notificationTapSubscription = null;
      if (tokenSubscription != null) {
        unawaited(tokenSubscription.cancel());
      }
      if (foregroundSubscription != null) {
        unawaited(foregroundSubscription.cancel());
      }
      if (tapSubscription != null) {
        unawaited(tapSubscription.cancel());
      }
      _session = _apiClient.captureSession();
      _registration.clear();
      _initializing = null;
    }
    return _session!;
  }

  void _scheduleRetry(ApiSession session) {
    if (!session.isActive || !_notificationsEnabled || _retryTimer != null) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _retryTimer = Timer(const Duration(seconds: 30), () {
      _retryTimer = null;
      if (session.isActive) unawaited(initializeForAuthenticatedUser());
    });
  }

  Future<void> _initialize(ApiSession session) async {
    if (appDemoMode || !_isSupportedPlatform) return;
    if (!_messagingReady) return;
    if (!_initialized) {
      WidgetsBinding.instance.addObserver(this);
      _initialized = true;
    }

    try {
      final messaging = _messaging;
      final preferences = await SharedPreferences.getInstance();
      session.checkActive();
      _notificationsEnabled = preferences.getBool(_enabledKey) ?? true;
      if (!_notificationsEnabled) activeNotifications.value = false;
      if (!_initialMessageRead) {
        final initialMessage = await messaging.getInitialMessage();
        session.checkActive();
        _initialMessageRead = true;
        if (initialMessage != null) {
          _initialTarget = _messageTarget(initialMessage);
        }
      }
      _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen((token) {
        if (session.isActive) unawaited(_syncToken(token, session: session));
      });
      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
        if (!session.isActive || !_notificationsEnabled) return;
        final target = _messageTarget(message);
        if (target == null) return;
        final type = message.data['type'];
        final id = type == 'meetup_created'
            ? message.data['meetupId']
            : message.data['requestId'];
        final body =
            message.notification?.body ??
            switch (type) {
              'meetup_created' => '小圈圈建立了集合點',
              'recognition_response' =>
                message.data['status'] == 'accepted' ? '對方回覆：快來' : '對方回覆：當前不方便',
              _ => '有同好想在現場找你認親',
            };
        unawaited(
          LocalNotificationService.instance.showRecognitionRequest(
            body,
            target: target,
            deliveryId: id == null ? message.messageId : '$type:$id',
            title: type == 'meetup_created' ? '集合通知' : '認親通知',
            canDeliver: () => session.isActive && _notificationsEnabled,
            deliveryScope: session,
          ),
        );
      });
      _notificationTapSubscription ??= FirebaseMessaging.onMessageOpenedApp
          .listen((message) {
            if (session.isActive && _notificationsEnabled) {
              _openMessageTarget(message);
            }
          });
      final settings = await messaging.getNotificationSettings();
      session.checkActive();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await messaging.getToken();
        session.checkActive();
        await _syncToken(token, session: session);
      } else {
        _registration.clear();
        activeNotifications.value = false;
      }
    } catch (error) {
      if (session.isActive) {
        _registration.clear();
        activeNotifications.value = false;
      }
      _scheduleRetry(session);
      if (kDebugMode) debugPrint('Notification initialization failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(initializeForAuthenticatedUser());
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  Future<void> requestPermission() async {
    if (!_isSupportedPlatform) {
      throw Exception('此平台尚未支援認親推播通知，請使用 Android 或 iOS App');
    }
    if (!_messagingReady) {
      throw Exception('通知服務尚未就緒，請重新開啟 App 後再試');
    }
    final session = _authenticatedSession();
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    session.checkActive();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      _registration.clear();
      activeNotifications.value = false;
      throw Exception('通知權限尚未開啟，請至系統設定允許通知');
    }
    final preferences = await SharedPreferences.getInstance();
    session.checkActive();
    await preferences.setBool(_enabledKey, true);
    session.checkActive();
    _notificationsEnabled = true;
    try {
      final token = await _messaging.getToken();
      session.checkActive();
      await _syncToken(token, session: session, required: true);
      session.checkActive();
    } catch (_) {
      if (session.isActive) {
        _registration.clear();
        activeNotifications.value = false;
      }
      _scheduleRetry(session);
      rethrow;
    }
    await initializeForAuthenticatedUser();
  }

  Future<void> dispose() async {
    activeNotifications.value = false;
    _session?.cancel();
    _session = null;
    _initializing = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _initialized = false;
    final subscriptions = <StreamSubscription<dynamic>>[
      if (_tokenRefreshSubscription != null) _tokenRefreshSubscription!,
      if (_foregroundSubscription != null) _foregroundSubscription!,
      if (_notificationTapSubscription != null) _notificationTapSubscription!,
    ];
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _notificationTapSubscription = null;
    _initialized = false;
    _registration.clear();
    _initialMessageRead = false;
    _initialTarget = null;
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  Future<void> deleteDeviceToken() async {
    if (!_isSupportedPlatform || !_messagingReady) return;
    try {
      await _messaging.deleteToken();
    } catch (error) {
      if (kDebugMode) debugPrint('Notification token deletion failed: $error');
    }
  }

  Future<void> _syncToken(
    String? token, {
    required ApiSession session,
    bool required = false,
  }) async {
    session.checkActive();
    if (!_notificationsEnabled && !required) return;
    if (token == null || token.isEmpty) {
      _registration.clear();
      activeNotifications.value = false;
      _scheduleRetry(session);
      if (required) throw Exception('無法取得通知識別碼，請稍後再試');
      return;
    }
    try {
      await _registration.sync(token, _platformName, session);
      session.checkActive();
      if (!_notificationsEnabled) {
        await _apiClient.deleteWithData(
          '/me/push-tokens',
          data: {'token': token},
          session: session,
        );
        session.checkActive();
        _registration.clear();
        activeNotifications.value = false;
        return;
      }
      activeNotifications.value = true;
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (error) {
      if (session.isActive) {
        _registration.clear();
        activeNotifications.value = false;
      }
      _scheduleRetry(session);
      if (required) rethrow;
      if (kDebugMode) debugPrint('FCM token sync failed: $error');
    }
  }

  bool get _isSupportedPlatform {
    if (_messagingOverride != null) return true;
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
    return currentEventNotificationTarget(message.data);
  }
}
