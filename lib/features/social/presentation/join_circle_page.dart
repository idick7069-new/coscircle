import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/utils/error_message.dart';
import 'social_page.dart';

class JoinCirclePage extends ConsumerStatefulWidget {
  const JoinCirclePage({super.key, required this.inviteCode});
  final String inviteCode;
  @override
  ConsumerState<JoinCirclePage> createState() => _JoinCirclePageState();
}

class _JoinCirclePageState extends ConsumerState<JoinCirclePage> {
  bool _joining = false;
  String? _error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('小圈圈邀請')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.diversity_3_outlined, size: 48),
            const SizedBox(height: 16),
            Text('邀請碼 ${widget.inviteCode}'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _joining ? null : _join,
              icon: const Icon(Icons.group_add_outlined),
              label: Text(_joining ? '加入中' : '加入小圈圈'),
            ),
            TextButton(
              onPressed: _joining ? null : () => context.go('/'),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await ref.read(socialRepositoryProvider).joinCircle(widget.inviteCode);
      ref.invalidate(circlesProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入小圈圈')));
        context.go('/');
      }
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }
}
