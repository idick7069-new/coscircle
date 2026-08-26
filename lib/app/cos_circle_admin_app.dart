import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/models/profile.dart';
import '../core/providers/theme_mode_provider.dart';
import '../core/repositories/auth_repository.dart';
import '../core/repositories/profile_repository.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_message.dart';
import '../features/admin/presentation/admin_dashboard_page.dart';
import '../shared/widgets/cos_ui.dart';

final _adminRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const _AdminGatePage()),
    GoRoute(
      path: '/login',
      builder: (context, state) => const _AdminGatePage(),
    ),
  ],
);

class CosCircleAdminApp extends ConsumerWidget {
  const CosCircleAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final theme = switch (themeMode) {
      CosCircleThemeMode.neonDark => AppTheme.dark,
      CosCircleThemeMode.morandiLight => AppTheme.morandi,
    };

    return MaterialApp.router(
      title: 'CosCircle Admin',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: AppTheme.dark,
      themeMode: themeMode == CosCircleThemeMode.neonDark
          ? ThemeMode.dark
          : ThemeMode.light,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _adminRouter,
    );
  }
}

class _AdminGatePage extends ConsumerStatefulWidget {
  const _AdminGatePage();

  @override
  ConsumerState<_AdminGatePage> createState() => _AdminGatePageState();
}

class _AdminGatePageState extends ConsumerState<_AdminGatePage> {
  late Future<UserProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _restoreAdminProfile();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AdminLoadingPage();
        }

        final profile = snapshot.data;
        if (profile?.isAdmin == true) {
          return const AdminDashboardPage();
        }

        return _AdminLoginPage(onAuthenticated: _reload);
      },
    );
  }

  Future<UserProfile?> _restoreAdminProfile() async {
    final token = await ref.read(authRepositoryProvider).restoreToken();
    if (token == null || token.isEmpty) return null;
    final profile = await ref.read(profileRepositoryProvider).currentProfile();
    if (profile?.isAdmin != true) {
      await ref.read(authRepositoryProvider).logout();
      return null;
    }
    return profile;
  }

  void _reload() {
    setState(() {
      _profileFuture = _restoreAdminProfile();
    });
  }
}

class _AdminLoadingPage extends StatelessWidget {
  const _AdminLoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const CosCard(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CosLoadingPulse(size: 22),
                SizedBox(width: 14),
                Expanded(child: Text('正在確認管理員登入狀態...')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLoginPage extends ConsumerStatefulWidget {
  const _AdminLoginPage({required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  ConsumerState<_AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<_AdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: CosCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CosIconBubble(
                    icon: Icons.admin_panel_settings_outlined,
                    color: scheme.primary,
                    size: 52,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'CosCircle Admin',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '請使用管理員帳號登入。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: '密碼',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _errorText!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? CosLoadingPulse(color: scheme.onPrimary, size: 18)
                        : const Icon(Icons.login),
                    label: Text(_loading ? '登入中...' : '登入後台'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => _errorText = '請輸入有效 Email，密碼至少 8 個字元');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      if (session.user.isAdmin != true) {
        await ref.read(authRepositoryProvider).logout();
        if (!mounted) return;
        setState(() => _errorText = '登入失敗：需要管理員權限');
        return;
      }
      widget.onAuthenticated();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = '登入失敗：${userFacingError(error)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
