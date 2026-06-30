import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/services/oobe_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';

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
    return AppPage(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: ListView(
        children: [
          const SizedBox(height: 28),
          const _LoginStageHero(),
          const SizedBox(height: 18),
          CosCard(
            child: Column(
              children: [
                _LoginModeSwitch(
                  isRegister: _isRegister,
                  onChanged: (value) {
                    setState(() {
                      _isRegister = value;
                      _errorText = null;
                    });
                  },
                ),
                const SizedBox(height: 18),
                if (_isRegister) ...[
                  TextField(
                    controller: _nickname,
                    decoration: const InputDecoration(labelText: '暱稱'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: '密碼',
                    helperText: '至少 8 個字元',
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  autofillHints: const [AutofillHints.password],
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  _LoginErrorBanner(message: _errorText!),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isRegister ? Icons.person_add : Icons.login),
                    label: Text(_isRegister ? '建立帳號' : '登入'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '或使用社群帳號',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          _SocialLoginButton(
            icon: Icons.facebook,
            label: '使用 Facebook 登入',
            onPressed: _loading
                ? null
                : () => _showSocialTokenDialog(SocialLoginProvider.facebook),
          ),
          const SizedBox(height: 10),
          _SocialLoginButton(
            icon: Icons.chat_bubble_outline,
            label: '使用 LINE 登入',
            onPressed: _loading
                ? null
                : () => _showSocialTokenDialog(SocialLoginProvider.line),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreSession() async {
    final token = await ref.read(authRepositoryProvider).restoreToken();
    if (!mounted || token == null || token.isEmpty) return;
    await _goAfterRestoredAuth();
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
      builder: (context) => AlertDialog(
        title: Text('${provider.label} 登入'),
        content: TextField(
          controller: tokenController,
          decoration: InputDecoration(
            labelText: '${provider.label} access token',
            helperText: '正式版可接原生 SDK，這裡先支援 token 登入流程。',
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, tokenController.text),
            child: const Text('登入'),
          ),
        ],
      ),
    );
    tokenController.dispose();
    if (token == null || token.trim().isEmpty) return;
    await _socialLogin(provider, token.trim());
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
    if (!mounted || profile == null) return;
    final completed = await ref
        .read(oobeServiceProvider)
        .isCompleted(profile.id);
    if (!mounted) return;
    context.go(completed ? '/' : '/onboarding');
  }

  Future<void> _goAfterAuth(AuthSession session) async {
    final oobe = ref.read(oobeServiceProvider);
    if (!session.isNewUser) {
      await oobe.markCompleted(session.user.id);
    }
    final completed = await oobe.isCompleted(session.user.id);
    if (!mounted) return;
    context.go(session.isNewUser || !completed ? '/onboarding' : '/');
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
