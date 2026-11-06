import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';

class NotificationDeliveryHistory {
  final Set<String> _delivered = {};

  bool claim(String? id) {
    if (id == null) return true;
    if (!_delivered.add(id)) return false;
    if (_delivered.length > 100) _delivered.remove(_delivered.first);
    return true;
  }

  void forget(String? id) => _delivered.remove(id);
}

class LocalNotificationService {
  LocalNotificationService._()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _openTarget = ((target) => appRouter.go(target));

  @visibleForTesting
  LocalNotificationService.forTesting({
    required FlutterLocalNotificationsPlugin plugin,
    required void Function(String) openTarget,
  }) : _plugin = plugin,
       _openTarget = openTarget;

  static final instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(String) _openTarget;
  bool _initialized = false;
  Future<void>? _initializing;
  final _deliveries = NotificationDeliveryHistory();
  final _scopedDeliveries = Expando<NotificationDeliveryHistory>();
  final _tapTargets = <String, ({String target, bool Function() canDeliver})>{};
  final String _payloadPrefix = '${DateTime.now().microsecondsSinceEpoch}';
  int _nextId = 0;
  String? _initialPayload;

  String? _validTarget(String? payload) {
    final entry = _tapTargets[payload];
    return entry != null && entry.canDeliver() ? entry.target : null;
  }

  String? takeInitialTarget() {
    final target = _validTarget(_initialPayload);
    _initialPayload = null;
    return target;
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;
    final operation = _initialize();
    _initializing = operation;
    return operation.whenComplete(() {
      if (identical(_initializing, operation)) _initializing = null;
    });
  }

  Future<void> _initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final target = _validTarget(response.payload);
        if (target != null) _openTarget(target);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'recognition_requests',
            '認親通知',
            description: '現場認親請求、回覆與集合通知',
            importance: Importance.high,
          ),
        );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      // A previous process has no live session guard, so its payload is ignored.
      _initialPayload = launch?.notificationResponse?.payload;
    }
    _initialized = true;
  }

  Future<void> showMeetupChanged(
    String message, {
    bool Function()? canDeliver,
  }) async {
    if (canDeliver?.call() == false) return;
    final preferences = await SharedPreferences.getInstance();
    bool allowed() =>
        canDeliver?.call() != false &&
        preferences.getBool('recognition_notifications_enabled') != false;
    if (!allowed()) return;
    await initialize();
    if (!allowed()) return;
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1000000),
      title: 'CosCircle',
      body: message,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'meetup_updates',
          '集合通知',
          channelDescription: '小圈圈集合點更新與取消通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> showRecognitionRequest(
    String message, {
    String? target,
    String? deliveryId,
    String title = '有人想認親',
    bool Function()? canDeliver,
    Object? deliveryScope,
  }) async {
    if (canDeliver?.call() == false) return;
    final preferences = await SharedPreferences.getInstance();
    bool allowed() =>
        canDeliver?.call() != false &&
        preferences.getBool('recognition_notifications_enabled') != false;
    if (!allowed()) return;
    await initialize();
    if (!allowed()) return;
    final deliveries = deliveryScope == null
        ? _deliveries
        : (_scopedDeliveries[deliveryScope] ??= NotificationDeliveryHistory());
    if (!deliveries.claim(deliveryId)) return;
    final id = ++_nextId;
    final payload = target != null && target.startsWith('/current/')
        ? '$_payloadPrefix:$id'
        : null;
    if (payload != null) {
      _tapTargets.removeWhere((_, entry) => !entry.canDeliver());
      if (_tapTargets.length >= 100) _tapTargets.remove(_tapTargets.keys.first);
      _tapTargets[payload] = (target: target!, canDeliver: allowed);
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: message,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'recognition_requests',
            '認親通知',
            channelDescription: '現場認親請求與回覆通知',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      deliveries.forget(deliveryId);
      _tapTargets.remove(payload);
      rethrow;
    }
  }
}
