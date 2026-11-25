import '../../../core/services/apple_login_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/auth_repository.dart';
import '../../../core/services/line_login_service.dart';
import '../../../core/services/line_web_navigation.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'email_verification_section.dart';

final loginMethodsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(authRepositoryProvider).loginMethods();
});

class LoginMethodsPage extends ConsumerStatefulWidget {
  const LoginMethodsPage({super.key});

  @override
  ConsumerState<LoginMethodsPage> createState() => _LoginMethodsPageState();
}

class _LoginMethodsPageState extends ConsumerState<LoginMethodsPage> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (pendingLineWebResult() != null) {
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeWebLink());
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(loginMethodsProvider);
    return AppPage(
      appBar: AppBar(
        title: const Text('登入方式'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      child: methods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Column(
          children: [
            Text(userFacingError(error)),
            IconButton(
              tooltip: '重新讀取',
              onPressed: () => ref.invalidate(loginMethodsProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        data: (values) => ListView(
          children: [
            const CosPageHeader(
              title: '你的登入方式',
              subtitle: '管理目前帳號的登入與信箱驗證',
              leading: CosIconBubble(icon: Icons.manage_accounts_outlined),
            ),
            const SizedBox(height: 16),
            if (values.contains('email'))
              const EmailVerificationSection()
            else
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email／密碼'),
                subtitle: Text(values.contains('email') ? '已設定' : '未設定'),
              ),
            ListTile(
              leading: CosIconBubble(
                icon: Icons.chat_bubble_outline,
                color: Theme.of(context).colorScheme.secondary,
              ),
              title: const Text('LINE'),
              subtitle: Text(values.contains('line') ? '已綁定' : '未綁定'),
            ),
            if (!values.contains('line') &&
                values.contains('email') &&
                ref.watch(lineLoginAvailabilityProvider).asData?.value ==
                    true &&
                (kIsWeb || ref.watch(lineLoginServiceProvider).supported))
              OutlinedButton.icon(
                onPressed: _busy ? null : _linkLine,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: const Text('綁定 LINE'),
              ),
            if (values.contains('line')) ...[
              OutlinedButton.icon(
                onPressed: _busy || !values.contains('email')
                    ? null
                    : _unlinkLine,
                icon: const Icon(Icons.link_off),
                label: const Text('解綁 LINE'),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  values.contains('email')
                      ? '解綁後請使用 Email 登入，個人資料、好友與預定都會保留。'
                      : '目前只有 LINE 登入，需先有可用的 Email／密碼才能解綁。',
                ),
              ),
            ],
            if (values.contains('apple') ||
                ref.watch(appleLoginAvailabilityProvider).asData?.value ==
                    true) ...[
              ListTile(
                leading: const Icon(Icons.apple),
                title: const Text('Apple'),
                subtitle: Text(values.contains('apple') ? '已綁定' : '未綁定'),
              ),
              if (!values.contains('apple') && values.contains('email'))
                OutlinedButton.icon(
                  onPressed: _busy ? null : _linkApple,
                  icon: const Icon(Icons.link),
                  label: const Text('綁定 Apple'),
                ),
              if (!values.contains('apple'))
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('已有帳號請先在這裡綁定 Apple，再使用 Apple 登入；相同信箱不會自動合併帳號。'),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _linkApple() async {
    if (_busy) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ConfirmPasswordDialog(),
    );
    if (!mounted || password == null || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      final challenge = await repository.appleChallenge(purpose: 'link');
      if (!mounted) return;
      final credential = await ref
          .read(appleLoginServiceProvider)
          .authorize(challenge);
      if (!mounted || credential == null) return;
      await repository.linkApple(credential, password);
      if (!mounted) return;
      ref.invalidate(loginMethodsProvider);
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkLine() async {
    if (_busy) return;
    if (kIsWeb) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final url = await ref.read(authRepositoryProvider).startLineWebLink();
        if (mounted) redirectToLine(url);
      } catch (error) {
        if (mounted) setState(() => _error = userFacingError(error));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ConfirmPasswordDialog(),
    );
    if (!mounted || password == null || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await ref.read(lineLoginServiceProvider).authorize();
      if (!mounted || token == null) return;
      await ref
          .read(authRepositoryProvider)
          .linkLine(accessToken: token, password: password);
      if (mounted) {
        ref.invalidate(loginMethodsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('LINE 已綁定至目前帳號')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkLine() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final password = await showDialog<String>(
        context: context,
        builder: (_) => const _ConfirmPasswordDialog(unlink: true),
      );
      if (!mounted || password == null || password.isEmpty) return;
      await ref.read(authRepositoryProvider).unlinkLine(password: password);
      if (!mounted) return;
      ref.invalidate(loginMethodsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('LINE 已解綁，之後請使用 Email 登入')));
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeWebLink() async {
    final result = pendingLineWebResult();
    clearLineWebResult();
    try {
      if (result != 'complete') {
        throw StateError('LINE 授權已取消或未完成，請重新綁定');
      }
      final password = await showDialog<String>(
        context: context,
        builder: (_) => const _ConfirmPasswordDialog(),
      );
      if (!mounted || password == null || password.isEmpty) return;
      await ref
          .read(authRepositoryProvider)
          .completeLineWebLink(password: password);
      if (!mounted) return;
      ref.invalidate(loginMethodsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE 已綁定至目前帳號，可使用 Email 或 LINE 登入')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog({this.unlink = false});
  final bool unlink;

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.unlink ? '確認解綁 LINE' : '確認目前帳號'),
    content: TextField(
      controller: _controller,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Email 登入密碼'),
      enableSuggestions: false,
      autocorrect: false,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.unlink ? '確認解綁' : '繼續'),
      ),
    ],
  );
}
