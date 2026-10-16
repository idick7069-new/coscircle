import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';

enum EmailActionMode { forgot, verify, reset }

class EmailActionPage extends ConsumerStatefulWidget {
  const EmailActionPage({
    super.key,
    required this.mode,
    this.token,
    this.email = '',
  });
  final EmailActionMode mode;
  final String? token;
  final String email;
  @override
  ConsumerState<EmailActionPage> createState() => _EmailActionPageState();
}

class _EmailActionPageState extends ConsumerState<EmailActionPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false, _completed = false, _obscure = true;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;
  bool get _validToken =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(widget.token ?? '');
  @override
  void initState() {
    super.initState();
    _email.text = widget.email;
    if (widget.mode != EmailActionMode.forgot && !_validToken) {
      _error = '連結不完整或已失效，請重新申請';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    EmailActionMode.forgot => '忘記密碼',
    EmailActionMode.verify => '驗證信箱',
    EmailActionMode.reset => '重設密碼',
  };

  Future<void> _submit() async {
    if (_busy || _cooldown > 0 || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (widget.mode != EmailActionMode.forgot && !_validToken) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      switch (widget.mode) {
        case EmailActionMode.forgot:
          await auth.forgotPassword(_email.text.trim());
        case EmailActionMode.verify:
          await auth.verifyEmail(widget.token!);
        case EmailActionMode.reset:
          await auth.resetPassword(
            token: widget.token!,
            password: _password.text,
          );
      }
      if (!mounted) return;
      setState(() {
        _completed = true;
        _password.clear();
        _confirm.clear();
      });
      if (widget.mode == EmailActionMode.forgot) {
        setState(() => _cooldown = 60);
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return timer.cancel();
          setState(() => _cooldown--);
          if (_cooldown <= 0) timer.cancel();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    appBar: AppBar(title: Text(_title)),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            children: [
              const SizedBox(height: 24),
              Icon(
                _completed ? Icons.check_circle_outline : Icons.mail_outline,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              if (_completed) ...[
                Text(switch (widget.mode) {
                  EmailActionMode.forgot =>
                    '申請已送出。若此信箱已設定密碼登入，你會收到重設信，請也查看垃圾郵件。',
                  EmailActionMode.verify => '信箱驗證完成。',
                  EmailActionMode.reset => '密碼已重設，請使用新密碼重新登入。',
                }),
                const SizedBox(height: 16),
                if (widget.mode == EmailActionMode.forgot)
                  OutlinedButton.icon(
                    onPressed: _cooldown > 0 || _busy ? null : _submit,
                    icon: const Icon(Icons.refresh),
                    label: Text(_cooldown > 0 ? '$_cooldown 秒後可重寄' : '重新申請'),
                  ),
                FilledButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.login),
                  label: const Text('前往登入'),
                ),
              ] else ...[
                if (widget.mode == EmailActionMode.forgot)
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: '註冊信箱',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : '請輸入有效信箱',
                    onFieldSubmitted: (_) => _submit(),
                  ),
                if (widget.mode == EmailActionMode.verify)
                  const Text('確認驗證這封信所對應的 CosCircle 帳號信箱？'),
                if (widget.mode == EmailActionMode.reset) ...[
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: '新密碼',
                      helperText: '至少 8 個字元',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? '顯示密碼' : '隱藏密碼',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value != null &&
                            value.length >= 8 &&
                            value.length <= 1024
                        ? null
                        : '密碼須為 8 至 1024 個字元',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '再次輸入新密碼'),
                    validator: (value) =>
                        value == _password.text ? null : '兩次密碼不一致',
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed:
                      _busy ||
                          (widget.mode != EmailActionMode.forgot &&
                              !_validToken)
                      ? null
                      : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    widget.mode == EmailActionMode.forgot
                        ? '寄送重設連結'
                        : widget.mode == EmailActionMode.verify
                        ? '確認驗證信箱'
                        : '更新密碼',
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_error != null && widget.mode != EmailActionMode.forgot)
                TextButton(
                  onPressed: () => context.go(
                    widget.mode == EmailActionMode.reset
                        ? '/forgot-password'
                        : '/login',
                  ),
                  child: Text(
                    widget.mode == EmailActionMode.reset ? '重新申請重設連結' : '返回登入',
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
