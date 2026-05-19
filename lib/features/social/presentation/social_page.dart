import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/circle.dart';
import '../../../core/repositories/social_repository.dart';

final circlesProvider = FutureProvider.autoDispose<List<CircleGroup>>((ref) {
  return ref.watch(socialRepositoryProvider).fetchCircles();
});

class SocialPage extends ConsumerWidget {
  const SocialPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(circlesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(circlesProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '社交',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _ActionTile(
            icon: Icons.group_add,
            title: '新建小圈圈',
            subtitle: '命名後自動產生邀請碼與網址',
            onTap: () => _circleDialog(context, ref, create: true),
          ),
          _ActionTile(
            icon: Icons.qr_code,
            title: '加入小圈圈',
            subtitle: '透過邀請碼或網址加入',
            onTap: () => _circleDialog(context, ref, create: false),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的小圈圈',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '重新整理',
                onPressed: () => ref.invalidate(circlesProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          circles.when(
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('尚未加入任何小圈圈'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final circle in items)
                    _CircleCard(
                      circle: circle,
                      onLeave: () => _confirmLeave(context, ref, circle),
                    ),
                ],
              );
            },
            error: (error, stack) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('小圈圈載入失敗：$error'),
              ),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _circleDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool create,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CircleDialog(create: create),
    );
  }

  Future<void> _confirmLeave(
    BuildContext context,
    WidgetRef ref,
    CircleGroup circle,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('離開小圈圈'),
        content: Text('確定要離開「${circle.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('離開'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(socialRepositoryProvider).leaveCircle(circle.id);
    ref.invalidate(circlesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已離開小圈圈')));
  }
}

class _CircleDialog extends ConsumerStatefulWidget {
  const _CircleDialog({required this.create});

  final bool create;

  @override
  ConsumerState<_CircleDialog> createState() => _CircleDialogState();
}

class _CircleDialogState extends ConsumerState<_CircleDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final create = widget.create;

    return AlertDialog(
      title: Text(create ? '新建小圈圈' : '加入小圈圈'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: create ? '小圈圈名稱' : '邀請碼或網址'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final value = _controller.text.trim();
            if (value.isEmpty) return;
            if (create) {
              await ref.read(socialRepositoryProvider).createCircle(value);
            } else {
              await ref.read(socialRepositoryProvider).joinCircle(value);
            }
            ref.invalidate(circlesProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(create ? '建立' : '加入'),
        ),
      ],
    );
  }
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.circle, required this.onLeave});

  final CircleGroup circle;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.groups)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circle.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${circle.memberCount} 位成員${circle.isOwner ? ' · 我建立的' : ''}',
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'leave') onLeave();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'leave', child: Text('離開')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(circle.inviteCode)),
                Text(
                  circle.inviteUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
