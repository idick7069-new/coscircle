import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repositories/auth_repository.dart';
import '../../../core/services/line_login_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';
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
  Widget build(BuildContext context) {
    final methods = ref.watch(loginMethodsProvider);
    return AppPage(
      appBar: AppBar(title: const Text('登入方式')),
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
            if (values.contains('email'))
              const EmailVerificationSection()
            else
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email／密碼'),
                subtitle: Text(values.contains('email') ? '已設定' : '未設定'),
              ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('LINE'),
              subtitle: Text(values.contains('line') ? '已綁定' : '未綁定'),
            ),
            if (!values.contains('line') &&
                values.contains('email') &&
                ref.watch(lineLoginEnabledProvider) &&
                ref.watch(lineLoginServiceProvider).supported)
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

  Future<void> _linkLine() async {
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
}

class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog();

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
    title: const Text('確認目前帳號'),
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
        child: const Text('繼續'),
      ),
    ],
  );
}
