import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/cos_circle_app.dart';
import 'core/services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW');
  try {
    await LocalNotificationService.instance.initialize();
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Notification initialization failed: $error');
    }
  }

  runApp(const ProviderScope(child: CosCircleApp()));
}
