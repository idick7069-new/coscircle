import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/services/line_login_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../../shared/widgets/cos_animated_logo.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _errorText;
  bool _restoreFailed = false;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoringSession || _restoreFailed) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_restoringSession) ...[
                      const CosAnimatedLogo(),
                      const SizedBox(height: 20),
                      const Text('正在確認登入狀態'),
                    ] else ...[
                      Icon(
                        Icons.wifi_off_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorText ?? '無法確認登入狀態',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _restoreSession,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新連線'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _restoreFailed = false;
                          _errorText = null;
                        }),
                        child: const Text('使用其他帳號登入'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return AppPage(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: ListView(
        children: [
          const SizedBox(height: 28),
          const _LoginStageHero(),
          const SizedBox(height: 18),
          _LoginAccessCard(
            isRegister: _isRegister,
            loading: _loading,
            errorText: _errorText,
            nicknameController: _nickname,
            emailController: _email,
            passwordController: _password,
            onModeChanged: (value) {
              setState(() {
                _isRegister = value;
                _errorText = null;
              });
            },
            onSubmit: _submit,
          ),
          const SizedBox(height: 16),
          if (ref.watch(lineLoginEnabledProvider) &&
              ref.watch(lineLoginServiceProvider).supported)
            OutlinedButton.icon(
              onPressed: _loading ? null : _lineLogin,
              icon: const Icon(Icons.login),
              label: const Text('使用 LINE 登入'),
            ),
          if (const bool.fromEnvironment('ENABLE_SOCIAL_TOKEN_LOGIN'))
            _SocialLoginPanel(
              loading: _loading,
              onFacebook: () =>
                  _showSocialTokenDialog(SocialLoginProvider.facebook),
              onLine: () => _showSocialTokenDialog(SocialLoginProvider.line),
            ),
        ],
      ),
    );
  }

  Future<void> _restoreSession() async {
    var navigating = false;
    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _restoringSession = true;
          _restoreFailed = false;
          _errorText = null;
        });
      }
      final token = await ref.read(authRepositoryProvider).restoreToken();
      if (!mounted || token == null || token.isEmpty) return;
      await _goAfterRestoredAuth();
      navigating = true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _restoreFailed = true;
          _errorText = '無法恢復登入：${userFacingError(error)}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          // Keep the form hidden while asynchronous router redirects finish.
          if (!navigating) _restoringSession = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final nickname = _nickname.text.trim().isEmpty
        ? '圈圈新朋友'
        : _nickname.text.trim();

    if (!email.contains('@') || password.length < 8) {
      setState(() => _errorText = '請輸入有效 Email，密碼至少 8 個字元');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      late final AuthSession session;
      if (_isRegister) {
        session = await auth.register(
          nickname: nickname,
          email: email,
          password: password,
        );
      } else {
        session = await auth.login(email: email, password: password);
      }
      if (mounted) await _goAfterAuth(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = _isRegister
            ? '註冊失敗：${userFacingError(error)}'
            : '登入失敗：${userFacingError(error)}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showSocialTokenDialog(SocialLoginProvider provider) async {
    final tokenController = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) =>
          _SocialTokenDialog(provider: provider, controller: tokenController),
    );
    tokenController.dispose();
    if (token == null || token.trim().isEmpty) return;
    await _socialLogin(provider, token.trim());
  }

  Future<void> _lineLogin() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final token = await ref.read(lineLoginServiceProvider).authorize();
      if (!mounted || token == null) return;
      final session = await ref
          .read(authRepositoryProvider)
          .socialLogin(provider: SocialLoginProvider.line, accessToken: token);
      if (mounted) await _goAfterAuth(session);
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = 'LINE 登入失敗：${userFacingError(error)}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _socialLogin(
    SocialLoginProvider provider,
    String accessToken,
  ) async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .socialLogin(provider: provider, accessToken: accessToken);
      if (mounted) await _goAfterAuth(session);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorText = '${provider.label} 登入失敗：${userFacingError(error)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goAfterRestoredAuth() async {
    final profile = await ref.read(profileRepositoryProvider).currentProfile();
    if (!mounted) return;
    if (profile == null) throw Exception('無法讀取帳號資料，請重新連線');
    await ref
        .read(pushNotificationServiceProvider)
        .initializeForAuthenticatedUser();
    final completed = profile.onboardingCompleted;
    if (!mounted) return;
    _navigateAfterAuth(completed);
  }

  Future<void> _goAfterAuth(AuthSession session) async {
    await ref
        .read(pushNotificationServiceProvider)
        .initializeForAuthenticatedUser();
    final completed = session.user.onboardingCompleted;
    if (!mounted) return;
    _navigateAfterAuth(completed);
  }

  void _navigateAfterAuth(bool completed) {
    final next = safeReturnPath(
      ref.read(pushNotificationServiceProvider).takeInitialTarget() ??
          GoRouterState.of(context).uri.queryParameters['next'],
    );
    context.go(
      completed
          ? next
          : Uri(
              path: '/onboarding',
              queryParameters: {'next': next},
            ).toString(),
    );
  }
}

class _LoginAccessCard extends StatelessWidget {
  const _LoginAccessCard({
    required this.isRegister,
    required this.loading,
    required this.errorText,
    required this.nicknameController,
    required this.emailController,
    required this.passwordController,
    required this.onModeChanged,
    required this.onSubmit,
  });

  final bool isRegister;
  final bool loading;
  final String? errorText;
  final TextEditingController nicknameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosSectionHeader(
            title: isRegister ? '建立入場通行證' : '回到你的同好圈',
            subtitle: isRegister
                ? '建立名片後，就能加入場次、設定小圈圈與分享預定'
                : '登入後同步你的活動預定、同好訊號與安全設定',
            icon: isRegister
                ? Icons.person_add_alt_1_outlined
                : Icons.login_outlined,
            trailing: CosBadge(
              label: isRegister ? '新朋友' : '已登錄',
              icon: isRegister
                  ? Icons.auto_awesome_outlined
                  : Icons.verified_user_outlined,
              highlighted: true,
              color: isRegister ? scheme.secondary : scheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          _LoginModeSwitch(isRegister: isRegister, onChanged: onModeChanged),
          const SizedBox(height: 18),
          if (isRegister) ...[
            TextField(
              controller: nicknameController,
              decoration: const InputDecoration(
                labelText: '暱稱',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: '密碼',
              helperText: '至少 8 個字元',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            obscureText: true,
            onSubmitted: (_) => onSubmit(),
            autofillHints: const [AutofillHints.password],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 10),
            _LoginErrorBanner(message: errorText!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onSubmit,
              icon: loading
                  ? CosLoadingPulse(color: scheme.onPrimary, size: 20)
                  : Icon(isRegister ? Icons.person_add : Icons.login),
              label: Text(isRegister ? '建立帳號' : '登入'),
            ),
          ),
          if (!isRegister)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: loading
                    ? null
                    : () => context.push(
                        Uri(
                          path: '/forgot-password',
                          queryParameters: {
                            'email': emailController.text.trim(),
                          },
                        ).toString(),
                      ),
                child: const Text('忘記密碼？'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SocialTokenDialog extends StatelessWidget {
  const _SocialTokenDialog({required this.provider, required this.controller});

  final SocialLoginProvider provider;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      clipBehavior: Clip.antiAlias,
      child: CosGradientPanel(
        icon: provider == SocialLoginProvider.facebook
            ? Icons.facebook
            : Icons.chat_bubble_outline,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosSectionHeader(
              title: '${provider.label} 登入',
              subtitle: '正式版可接原生 SDK，這裡先支援 token 登入流程',
              icon: provider == SocialLoginProvider.facebook
                  ? Icons.facebook
                  : Icons.chat_bubble_outline,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${provider.label} access token',
                prefixIcon: Icon(Icons.vpn_key_outlined, color: scheme.primary),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, controller.text),
                    icon: const Icon(Icons.login),
                    label: const Text('登入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginStageHero extends StatelessWidget {
  const _LoginStageHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CosUi.radiusXl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer,
            scheme.tertiaryContainer,
          ],
        ),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -20,
            child: Icon(
              Icons.auto_awesome,
              size: 132,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CosLogoMark(size: 64),
                    const Spacer(),
                    CosBadge(
                      label: 'Cos小圈圈',
                      icon: Icons.diversity_3_outlined,
                      highlighted: true,
                      color: scheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'CosCircle',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '活動現場找同好、公開出席宣告、分享位置與管理小圈圈。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: CosMetricTile(
                        icon: Icons.radar_outlined,
                        label: '現場雷達',
                        value: '找人',
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CosMetricTile(
                        icon: Icons.qr_code_2,
                        label: '快速交換',
                        value: '名片',
                        color: scheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CosMetricTile(
                        icon: Icons.event_available_outlined,
                        label: '活動預定',
                        value: '約場',
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginModeSwitch extends StatelessWidget {
  const _LoginModeSwitch({required this.isRegister, required this.onChanged});

  final bool isRegister;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            Expanded(
              child: _LoginModeButton(
                icon: Icons.login,
                label: '登入',
                selected: !isRegister,
                onTap: () => onChanged(false),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _LoginModeButton(
                icon: Icons.person_add_alt_1_outlined,
                label: '註冊',
                selected: isRegister,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginModeButton extends StatelessWidget {
  const _LoginModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(CosUi.radiusMd),
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.32)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginErrorBanner extends StatelessWidget {
  const _LoginErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialLoginPanel extends StatelessWidget {
  const _SocialLoginPanel({
    required this.loading,
    required this.onFacebook,
    required this.onLine,
  });

  final bool loading;
  final VoidCallback onFacebook;
  final VoidCallback onLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.54),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CosIconBubble(
                  icon: Icons.hub_outlined,
                  color: scheme.tertiary,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '社群帳號',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '正式版可接原生 SDK，這裡先保留 token 登入流程',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SocialLoginButton(
              icon: Icons.facebook,
              label: '使用 Facebook 登入',
              onPressed: loading ? null : onFacebook,
            ),
            const SizedBox(height: 10),
            _SocialLoginButton(
              icon: Icons.chat_bubble_outline,
              label: '使用 LINE 登入',
              onPressed: loading ? null : onLine,
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
