import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/router/app_router.dart';
import '../core/providers/theme_mode_provider.dart';
import '../core/theme/app_theme.dart';

class CosCircleApp extends ConsumerWidget {
  const CosCircleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final theme = switch (themeMode) {
      CosCircleThemeMode.neonDark => AppTheme.dark,
      CosCircleThemeMode.morandiLight => AppTheme.morandi,
    };

    return MaterialApp.router(
      title: 'CosCircle | Cos小圈圈',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: AppTheme.dark,
      themeMode: themeMode == CosCircleThemeMode.neonDark
          ? ThemeMode.dark
          : ThemeMode.light,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: appRouter,
    );
  }
}
