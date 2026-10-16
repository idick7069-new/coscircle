import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/utils/error_message.dart';

final authEmailStatusProvider = FutureProvider.autoDispose<AuthEmailStatus>(
  (ref) => ref.watch(authRepositoryProvider).emailStatus(),
);

class EmailVerificationSection extends ConsumerStatefulWidget {
  const EmailVerificationSection({super.key});
  @override
  ConsumerState<EmailVerificationSection> createState() =>
      _EmailVerificationSectionState();
}

class _EmailVerificationSectionState
    extends ConsumerState<EmailVerificationSection> {
  bool _busy = false;
  int _cooldown = 0;
  String? _message;
  bool _failed = false;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _cooldown > 0) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await ref.read(authRepositoryProvider).requestEmailVerification();
      if (!mounted) return;
      ref.invalidate(authEmailStatusProvider);
      setState(() {
        _message = '驗證信已安排寄送，請查看信箱與垃圾郵件。';
        _cooldown = 60;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        setState(() => _cooldown--);
        if (_cooldown <= 0) timer.cancel();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = userFacingError(error);
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(authEmailStatusProvider)
      .when(
        loading: () => const ListTile(
          leading: Icon(Icons.email_outlined),
          title: Text('Email／密碼'),
          subtitle: Text('讀取中'),
        ),
        error: (error, _) => ListTile(
          title: const Text('Email／密碼'),
          subtitle: Text(userFacingError(error)),
          trailing: IconButton(
            tooltip: '重新讀取信箱狀態',
            onPressed: () => ref.invalidate(authEmailStatusProvider),
            icon: const Icon(Icons.refresh),
          ),
        ),
        data: (status) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                status.verified
                    ? Icons.verified_outlined
                    : Icons.email_outlined,
              ),
              title: const Text('Email／密碼'),
              subtitle: Text(
                '${status.email ?? "未設定"}\n${status.verified ? "信箱已驗證" : "信箱未驗證"}',
              ),
              trailing: IconButton(
                tooltip: '重新讀取信箱狀態',
                onPressed: () => ref.invalidate(authEmailStatusProvider),
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (status.email != null && !status.verified)
              OutlinedButton.icon(
                onPressed: _busy || _cooldown > 0 || !status.available
                    ? null
                    : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mark_email_read_outlined),
                label: Text(
                  _cooldown > 0
                      ? '$_cooldown 秒後可重寄'
                      : status.available
                      ? '寄送驗證信'
                      : '寄信服務暫時無法使用',
                ),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _failed ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ),
          ],
        ),
      );
}
