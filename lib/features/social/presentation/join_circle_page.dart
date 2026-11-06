import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../../shared/widgets/cos_illustration.dart';
import 'friendship_widgets.dart' show refreshFriendships;

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
  Widget build(BuildContext context) => AppPage(
    appBar: AppBar(title: const Text('小圈圈邀請')),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CosIllustration(height: 144),
              const SizedBox(height: 16),
              const CosSectionHeader(
                title: '一起加入小圈圈',
                icon: Icons.diversity_3_outlined,
              ),
              const SizedBox(height: 16),
              SelectableText(
                '邀請碼 ${widget.inviteCode}',
                textAlign: TextAlign.center,
              ),
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
    ),
  );
  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await ref.read(socialRepositoryProvider).joinCircle(widget.inviteCode);
      if (!mounted) return;
      refreshFriendships(ref);
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
