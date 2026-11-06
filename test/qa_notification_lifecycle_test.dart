import 'dart:async';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/services/local_notification_service.dart';
import 'package:coscircle/core/services/push_notification_service.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalPlugin implements FlutterLocalNotificationsPlugin {
  Completer<void>? initializeGate;
  final initializeStarted = Completer<void>();
  int initializeCalls = 0;
  bool failShow = false;
  final shown = <({int id, String? body, String? payload})>[];
  DidReceiveNotificationResponseCallback? onTap;
  NotificationAppLaunchDetails? launchDetails;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls++;
    onTap = onDidReceiveNotificationResponse;
    if (!initializeStarted.isCompleted) initializeStarted.complete();
    await initializeGate?.future;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launchDetails;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (failShow) throw StateError('plugin failed');
    shown.add((id: id, body: body, payload: payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #resolvePlatformSpecificImplementation) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  void tap(String? payload) => onTap!(
    NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: payload,
    ),
  );
}

class _Settings implements NotificationSettings {
  @override
  AuthorizationStatus get authorizationStatus => AuthorizationStatus.authorized;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Messaging implements FirebaseMessaging {
  String? token = 'device-token';
  final refresh = StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  Future<NotificationSettings> getNotificationSettings() async => _Settings();
  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async => token;
  @override
  Future<void> deleteToken() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RegistrationApi extends ApiClient {
  _RegistrationApi() : super(baseUrl: 'https://example.invalid/api');
  bool failRegistration = false;
  int registrations = 0;
  Completer<void>? gate;

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    ApiSession? session,
  }) async {
    expectSync(path, '/me/push-tokens');
    session!.checkActive();
    registrations++;
    await gate?.future;
    if (failRegistration) throw StateError('registration failed');
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {},
    );
  }

  @override
  Future<Response<dynamic>> deleteWithData(
    String path, {
    required Object data,
    ApiSession? session,
  }) async {
    session!.checkActive();
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {},
    );
  }
}

// Firebase's static streams can complete cancellation in the outer real zone.
Future<void> _finishPhase(
  WidgetTester tester,
  String phase,
  Future<void> operation,
) async {
  var completed = false;
  Object? error;
  StackTrace? stack;
  operation.then(
    (_) => completed = true,
    onError: (Object caught, StackTrace trace) {
      error = caught;
      stack = trace;
      completed = true;
    },
  );
  for (var pump = 0; pump < 20 && !completed; pump++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(completed, isTrue, reason: '$phase did not complete after 20 pumps');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'queued foreground delivery is dropped after account changes during init',
    () async {
      final plugin = _LocalPlugin()..initializeGate = Completer<void>();
      final service = LocalNotificationService.forTesting(
        plugin: plugin,
        openTarget: (_) {},
      );
      final api = _RegistrationApi()..setAuthToken('account-a');
      final a = api.captureSession();
      final pending = service.showRecognitionRequest(
        'account-a',
        target: '/current/a?dayIndex=1',
        deliveryId: 'request:1',
        deliveryScope: a,
        canDeliver: () => a.isActive,
      );
      await plugin.initializeStarted.future;
      api.setAuthToken('account-b');
      final b = api.captureSession();
      final next = service.showRecognitionRequest(
        'account-b',
        deliveryId: 'request:1',
        deliveryScope: b,
        canDeliver: () => b.isActive,
      );
      plugin.initializeGate!.complete();
      await Future.wait([pending, next]);
      expect(plugin.initializeCalls, 1);
      expect(plugin.shown.map((n) => n.body), ['account-b']);
      a.cancel();
      b.cancel();
    },
  );

  test(
    'same delivery id deduplicates per session and old taps cannot open in B',
    () async {
      final plugin = _LocalPlugin();
      final opened = <String>[];
      final service = LocalNotificationService.forTesting(
        plugin: plugin,
        openTarget: opened.add,
      );
      final api = _RegistrationApi()..setAuthToken('account-a');
      final a = api.captureSession();
      Future<void> deliver(ApiSession session, String label) =>
          service.showRecognitionRequest(
            label,
            target: '/current/$label?dayIndex=1',
            deliveryId: 'shared-id',
            deliveryScope: session,
            canDeliver: () => session.isActive,
          );
      await Future.wait([deliver(a, 'a'), deliver(a, 'a')]);
      expect(plugin.shown, hasLength(1));
      final oldPayload = plugin.shown.single.payload;
      plugin.tap(oldPayload);
      expect(opened, ['/current/a?dayIndex=1']);
      opened.clear();
      api.setAuthToken('account-b');
      final b = api.captureSession();
      plugin.tap(oldPayload);
      expect(opened, isEmpty);
      await deliver(b, 'b');
      expect(plugin.shown, hasLength(2));
      expect(plugin.shown[0].id, isNot(plugin.shown[1].id));
      plugin.tap(plugin.shown.last.payload);
      expect(opened, ['/current/b?dayIndex=1']);
      b.cancel();
    },
  );

  test(
    'guard is rechecked after preferences before any initialization',
    () async {
      final plugin = _LocalPlugin();
      final service = LocalNotificationService.forTesting(
        plugin: plugin,
        openTarget: (_) {},
      );
      var active = true;
      final pending = service.showRecognitionRequest(
        'stale',
        canDeliver: () => active,
      );
      active = false;
      await pending;
      expect(plugin.initializeCalls, 0);
      expect(plugin.shown, isEmpty);
    },
  );

  test(
    'meetup session guard blocks delivery after delayed initialization',
    () async {
      final plugin = _LocalPlugin()..initializeGate = Completer<void>();
      final service = LocalNotificationService.forTesting(
        plugin: plugin,
        openTarget: (_) {},
      );
      var active = true;
      final pending = service.showMeetupChanged(
        'stale meetup',
        canDeliver: () => active,
      );
      await plugin.initializeStarted.future;
      active = false;
      plugin.initializeGate!.complete();
      await pending;
      expect(plugin.shown, isEmpty);
    },
  );

  test(
    'turning preference off during init blocks recognition and meetup',
    () async {
      final plugin = _LocalPlugin()..initializeGate = Completer<void>();
      final service = LocalNotificationService.forTesting(
        plugin: plugin,
        openTarget: (_) {},
      );
      final pending = [
        service.showRecognitionRequest('recognition'),
        service.showMeetupChanged('meetup'),
      ];
      await plugin.initializeStarted.future;
      await (await SharedPreferences.getInstance()).setBool(
        'recognition_notifications_enabled',
        false,
      );
      plugin.initializeGate!.complete();
      await Future.wait(pending);
      expect(plugin.shown, isEmpty);
    },
  );

  test('failed plugin delivery can be retried in same scope', () async {
    final plugin = _LocalPlugin()..failShow = true;
    final service = LocalNotificationService.forTesting(
      plugin: plugin,
      openTarget: (_) {},
    );
    final scope = Object();
    Future<void> deliver() => service.showRecognitionRequest(
      'retry',
      deliveryId: '1',
      deliveryScope: scope,
    );
    await expectLater(deliver(), throwsStateError);
    plugin.failShow = false;
    await deliver();
    await deliver();
    expect(plugin.shown, hasLength(1));
  });

  test('unverified launch and raw old tap targets are ignored', () async {
    final plugin = _LocalPlugin()
      ..launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '/current/old?dayIndex=1',
        ),
      );
    final opened = <String>[];
    final service = LocalNotificationService.forTesting(
      plugin: plugin,
      openTarget: opened.add,
    );
    await service.initialize();
    expect(service.takeInitialTarget(), isNull);
    plugin.tap('/current/old?dayIndex=1');
    expect(opened, isEmpty);
  });

  testWidgets(
    'automatic retry publishes active state, failure, disable and dispose',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final api = _RegistrationApi()
        ..setAuthToken('account-a')
        ..failRegistration = true;
      final messaging = _Messaging();
      final push = PushNotificationService.forTesting(
        apiClient: api,
        messaging: messaging,
      );
      try {
        final states = <bool>[];
        push.activeNotifications.addListener(
          () => states.add(push.activeNotifications.value),
        );
        expect(push.activeNotifications.value, false);
        await _finishPhase(
          tester,
          'initial registration failure',
          push.initializeForAuthenticatedUser(),
        );
        expect(push.activeNotifications.value, false);
        expect(api.registrations, 1);
        api.failRegistration = false;
        await tester.pump(const Duration(seconds: 30));
        expect(api.registrations, 2);
        expect(push.activeNotifications.value, true);
        api.failRegistration = true;
        messaging.refresh.add('refreshed-token');
        await tester.pump();
        expect(push.activeNotifications.value, false);
        api.failRegistration = false;
        await tester.pump(const Duration(seconds: 30));
        expect(push.activeNotifications.value, true);
        final disable = push.setNotificationsEnabled(false);
        expect(push.activeNotifications.value, false);
        await _finishPhase(tester, 'disable', disable);
        await tester.pump(const Duration(seconds: 30));
        expect(push.activeNotifications.value, false);
        await _finishPhase(tester, 'restore enabled preference', () async {
          await (await SharedPreferences.getInstance()).setBool(
            'recognition_notifications_enabled',
            true,
          );
        }());
        await _finishPhase(
          tester,
          'register after disable',
          push.initializeForAuthenticatedUser(),
        );
        expect(push.activeNotifications.value, true);
        final disposing = push.dispose();
        expect(push.activeNotifications.value, false);
        await _finishPhase(tester, 'dispose active service', disposing);
        expect(states, [true, false, true, false, true, false]);
      } finally {
        await _finishPhase(
          tester,
          'retry test cleanup dispose',
          push.dispose(),
        );
        await _finishPhase(
          tester,
          'retry test cleanup close refresh',
          messaging.refresh.close(),
        );
      }
    },
  );

  testWidgets(
    'old registration completion cannot publish active after dispose',
    (tester) async {
      final api = _RegistrationApi()
        ..setAuthToken('account-a')
        ..gate = Completer<void>();
      final messaging = _Messaging();
      final push = PushNotificationService.forTesting(
        apiClient: api,
        messaging: messaging,
      );
      try {
        final pending = push.initializeForAuthenticatedUser();
        await tester.pump();
        expect(api.registrations, 1);
        await _finishPhase(
          tester,
          'dispose pending registration',
          push.dispose(),
        );
        api.setAuthToken('account-b');
        api.gate!.complete();
        await _finishPhase(tester, 'release old registration', pending);
        expect(push.activeNotifications.value, false);
        expect(push.registeredToken, isNull);
        await _finishPhase(
          tester,
          'register new session',
          push.initializeForAuthenticatedUser(),
        );
        expect(push.activeNotifications.value, true);
      } finally {
        // Release the fixture even when an earlier assertion fails.
        if (!api.gate!.isCompleted) api.gate!.complete();
        await _finishPhase(
          tester,
          'session test cleanup dispose',
          push.dispose(),
        );
        await _finishPhase(
          tester,
          'session test cleanup close refresh',
          messaging.refresh.close(),
        );
      }
    },
  );
}
