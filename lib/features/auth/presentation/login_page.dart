import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/auth_repository.dart';
import '../../../shared/widgets/app_page.dart';

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
          const SizedBox(height: 56),
          Text(
            'CosCircle',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Cos小圈圈', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(
            '活動現場找同好、公開出席宣告、分享位置與管理小圈圈。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    );
  }

  Future<void> _restoreSession() async {
    final token = await ref.read(authRepositoryProvider).restoreToken();
    if (!mounted || token == null || token.isEmpty) return;
    context.go('/');
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
      if (_isRegister) {
        await auth.register(
          nickname: nickname,
          email: email,
          password: password,
        );
      } else {
        await auth.login(email: email, password: password);
      }
      if (mounted) context.go(_isRegister ? '/onboarding' : '/');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = _isRegister
            ? '註冊失敗，請確認 Email 是否已被使用'
            : '登入失敗，請確認 Email 或密碼';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
