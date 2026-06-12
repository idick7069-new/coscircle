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
          CosCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CosLogoMark(size: 64),
                const SizedBox(height: 18),
                Text(
                  'CosCircle',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cos小圈圈',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                Text(
                  '活動現場找同好、公開出席宣告、分享位置與管理小圈圈。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    CosBadge(label: '認親', icon: Icons.waving_hand_outlined),
                    CosBadge(label: '小圈圈', icon: Icons.diversity_3_outlined),
                    CosBadge(label: '活動雷達', icon: Icons.radar_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          CosCard(
            child: Column(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('登入')),
                    ButtonSegment(value: true, label: Text('註冊')),
                  ],
                  selected: {_isRegister},
                  onSelectionChanged: (value) {
                    setState(() {
                      _isRegister = value.first;
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
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
