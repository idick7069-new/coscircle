// Internal simulator probe. Never use this target for App Store distribution.
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:coscircle/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var success = false;
  try {
    final app = await Firebase.initializeApp();
    final expected = DefaultFirebaseOptions.currentPlatform;
    if (app.options.appId != expected.appId ||
        app.options.projectId != expected.projectId) {
      throw StateError('Native and build Firebase configuration do not match');
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    success =
        app.options.projectId == 'coscircle' &&
        app.options.appId.contains(':ios:');
    debugPrint(
      '${success ? 'FIREBASE_IOS_PROBE_PASS' : 'FIREBASE_IOS_PROBE_FAIL'} ${jsonEncode({'projectId': app.options.projectId, 'appId': app.options.appId, 'iosBundleId': app.options.iosBundleId, 'notificationSettingsReadable': true, 'nativeConfigMatchesBuildDefinitions': true, 'authorizationStatus': settings.authorizationStatus.name, 'pushDeliveryTested': false})}',
    );
  } catch (error) {
    debugPrint('FIREBASE_IOS_PROBE_FAIL ${error.runtimeType}');
  }
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            success ? 'Firebase iOS verified' : 'Firebase verification failed',
          ),
        ),
      ),
    ),
  );
}
