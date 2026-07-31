import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_environment.dart';
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
      builder: (context, child) =>
          _CosCircleDemoBanner(child: _CosCircleWebFrame(child: child)),
    );
  }
}

class _CosCircleDemoBanner extends StatelessWidget {
  const _CosCircleDemoBanner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!appDemoMode) return child;
    return Banner(
      message: 'DEMO',
      location: BannerLocation.topEnd,
      color: Theme.of(context).colorScheme.error,
      child: child,
    );
  }
}

class _CosCircleWebFrame extends StatelessWidget {
  const _CosCircleWebFrame({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    if (!kIsWeb) return content;
    if (_isAdminRoute(context)) return content;

    final size = MediaQuery.sizeOf(context);
    if (size.width < 760) return content;

    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.symmetric(
                vertical: BorderSide(color: scheme.outlineVariant),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.16),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  bool _isAdminRoute(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path.startsWith('/admin');
    } catch (_) {
      return false;
    }
  }
}
