import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

class CosCircleApp extends StatelessWidget {
  const CosCircleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CosCircle | Cos小圈圈',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: appRouter,
    );
  }
}
