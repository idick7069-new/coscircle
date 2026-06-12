import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/circle.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';

final circlesProvider = FutureProvider.autoDispose<List<CircleGroup>>((ref) {
  return ref.watch(socialRepositoryProvider).fetchCircles();
});

final followingProvider = FutureProvider.autoDispose<List<FollowedUser>>((ref) {
  return ref.watch(socialRepositoryProvider).fetchFollowing();
});

class SocialPage extends ConsumerWidget {
  const SocialPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(circlesProvider);
    final following = ref.watch(followingProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          CosPageHeader(
            title: '同好小圈圈',
            subtitle: '用 QR、作品和群組把活動現場的人串起來',
            leading: const CosIconBubble(icon: Icons.diversity_3_outlined),
            actions: [
              IconButton.filledTonal(
                tooltip: '掃描個人 QRCode',
                onPressed: () => context.push('/scan-profile'),
                icon: const Icon(Icons.qr_code_scanner),
              ),
              IconButton(
                tooltip: '重新整理',
                onPressed: () {
                  ref.invalidate(circlesProvider);
                  ref.invalidate(followingProvider);
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const TabBar(
            tabs: [
              Tab(text: '小圈圈', icon: Icon(Icons.groups_outlined)),
              Tab(text: '已關注', icon: Icon(Icons.favorite_border)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(circlesProvider),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _SocialActionGrid(
                        actions: [
                          _SocialAction(
                            icon: Icons.group_add,
                            title: '新建',
                            subtitle: '建立聚會小圈圈',
                            onTap: () =>
                                _circleDialog(context, ref, create: true),
                          ),
                          _SocialAction(
                            icon: Icons.qr_code,
                            title: '加入',
                            subtitle: '輸入邀請碼',
                            onTap: () =>
                                _circleDialog(context, ref, create: false),
                          ),
                          _SocialAction(
                            icon: Icons.qr_code_scanner,
                            title: '掃描',
                            subtitle: '掃 QR 找同好',
                            onTap: () => context.push('/scan-circle'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      circles.when(
                        data: (items) {
                          if (items.isEmpty) {
                            return _EmptyActionCard(
                              icon: Icons.groups_outlined,
                              title: '尚未加入任何小圈圈',
                              message: '建立自己的小圈圈，或掃描朋友的邀請碼加入。',
                              actionLabel: '掃描邀請碼',
                              onAction: () => context.push('/scan-circle'),
                            );
                          }
                          return Column(
                            children: [
                              for (final circle in items)
                                _CircleCard(
                                  circle: circle,
                                  onLeave: () =>
                                      _confirmLeave(context, ref, circle),
                                  onEdit: circle.isOwner
                                      ? () => _editCircle(context, ref, circle)
                                      : null,
                                  onOpenMember: (member) {
                                    if (member.publicCode.isEmpty) return;
                                    context.push(
                                      '/profiles/${member.publicCode}',
                                    );
                                  },
                                  onRemoveMember: circle.isOwner
                                      ? (member) => _confirmRemoveMember(
                                          context,
                                          ref,
                                          circle,
                                          member,
                                        )
                                      : null,
                                ),
                            ],
                          );
                        },
                        error: (error, stack) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('小圈圈載入失敗：${userFacingError(error)}'),
                          ),
                        ),
                        loading: () => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(followingProvider),
                  child: following.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _EmptyActionCard(
                              icon: Icons.favorite_border,
                              title: '尚未關注任何人',
                              message: '掃描對方的個人 QRCode，活動現場認親會更快。',
                              actionLabel: '掃描個人 QR',
                              onAction: () => context.push('/scan-profile'),
                            ),
                          ],
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final user in items)
                            _FollowedUserCard(
                              user: user,
                              onOpenProfile: () {
                                if (user.publicCode.isEmpty) return;
                                context.push('/profiles/${user.publicCode}');
                              },
                              onUnfollow: () =>
                                  _confirmUnfollow(context, ref, user),
                            ),
                        ],
                      );
                    },
                    error: (error, stack) => ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('關注清單載入失敗：${userFacingError(error)}'),
                          ),
                        ),
                      ],
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnfollow(
    BuildContext context,
    WidgetRef ref,
    FollowedUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消關注'),
        content: Text('確定要取消關注「${user.nickname}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消關注'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(socialRepositoryProvider).unfollowUser(user.userId);
    ref.invalidate(followingProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已取消關注')));
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

  Future<void> _editCircle(
    BuildContext context,
    WidgetRef ref,
    CircleGroup circle,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CircleDialog(create: true, circle: circle),
    );
  }

  Future<void> _confirmRemoveMember(
    BuildContext context,
    WidgetRef ref,
    CircleGroup circle,
    CircleMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除成員'),
        content: Text('確定要將「${member.nickname}」移出「${circle.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(socialRepositoryProvider)
        .removeCircleMember(circleId: circle.id, userId: member.userId);
    ref.invalidate(circlesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已移除小圈圈成員')));
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
  const _CircleDialog({required this.create, this.circle});

  final bool create;
  final CircleGroup? circle;

  @override
  ConsumerState<_CircleDialog> createState() => _CircleDialogState();
}

class _CircleDialogState extends ConsumerState<_CircleDialog> {
  final _controller = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final circle = widget.circle;
    if (circle != null) {
      _controller.text = circle.name;
      _descriptionController.text = circle.description;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final create = widget.create;
    final editing = widget.circle != null;

    return AlertDialog(
      title: Text(
        editing
            ? '編輯小圈圈'
            : create
            ? '新建小圈圈'
            : '加入小圈圈',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: create ? '小圈圈名稱' : '邀請碼或網址'),
          ),
          if (create) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '小圈圈說明'),
              maxLines: 3,
            ),
          ],
        ],
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
            final repository = ref.read(socialRepositoryProvider);
            if (editing) {
              await repository.updateCircle(
                circleId: widget.circle!.id,
                name: value,
                description: _descriptionController.text.trim(),
              );
            } else if (create) {
              await repository.createCircle(
                value,
                description: _descriptionController.text.trim(),
              );
            } else {
              await repository.joinCircle(value);
            }
            ref.invalidate(circlesProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(
            editing
                ? '儲存'
                : create
                ? '建立'
                : '加入',
          ),
        ),
      ],
    );
  }
}

class _EmptyActionCard extends StatelessWidget {
  const _EmptyActionCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosIconBubble(icon: icon, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(message),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({
    required this.circle,
    required this.onLeave,
    required this.onOpenMember,
    this.onEdit,
    this.onRemoveMember,
  });

  final CircleGroup circle;
  final VoidCallback onLeave;
  final VoidCallback? onEdit;
  final ValueChanged<CircleMember> onOpenMember;
  final ValueChanged<CircleMember>? onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CosCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          leading: CosIconBubble(
            icon: Icons.groups_2_outlined,
            color: circle.isOwner ? scheme.primary : scheme.secondary,
          ),
          title: Text(
            circle.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${circle.memberCount} 位成員${circle.isOwner ? ' · 我建立的' : ''}',
              ),
              if (circle.description.isNotEmpty)
                Text(
                  circle.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              _MemberAvatarStrip(members: circle.members),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit?.call();
              if (value == 'leave') onLeave();
            },
            itemBuilder: (context) => [
              if (onEdit != null)
                const PopupMenuItem(value: 'edit', child: Text('編輯')),
              const PopupMenuItem(value: 'leave', child: Text('離開')),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CosBadge(
                  label: circle.inviteCode,
                  icon: Icons.vpn_key_outlined,
                  highlighted: true,
                ),
                IconButton.filledTonal(
                  tooltip: '顯示邀請 QRCode',
                  onPressed: () => _showCircleQr(context),
                  icon: const Icon(Icons.qr_code_2),
                ),
                Text(
                  circle.inviteUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final member in circle.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: pickedImageProvider(member.avatarUrl),
                  child: member.avatarUrl.isEmpty
                      ? Text(member.nickname.characters.firstOrNull ?? '?')
                      : null,
                ),
                title: Text(
                  member.nickname.isEmpty ? '未命名使用者' : member.nickname,
                ),
                subtitle: member.isOwner ? const Text('建立者') : null,
                onTap: () => onOpenMember(member),
                trailing: !circle.isOwner || member.isOwner
                    ? null
                    : IconButton(
                        tooltip: '移除成員',
                        onPressed: () => onRemoveMember?.call(member),
                        icon: const Icon(Icons.person_remove_outlined),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCircleQr(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(circle.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: circle.inviteUrl.isEmpty
                  ? circle.inviteCode
                  : circle.inviteUrl,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            SelectableText(circle.inviteCode),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}

class _MemberAvatarStrip extends StatelessWidget {
  const _MemberAvatarStrip({required this.members});

  final List<CircleMember> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return CosAvatarStack(
      avatars: [
        for (final member in members) pickedImageProvider(member.avatarUrl),
      ],
      names: [for (final member in members) member.nickname],
      maxVisible: 8,
      radius: 12,
    );
  }
}

class _FollowedUserCard extends StatelessWidget {
  const _FollowedUserCard({
    required this.user,
    required this.onOpenProfile,
    required this.onUnfollow,
  });

  final FollowedUser user;
  final VoidCallback onOpenProfile;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CosCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundImage: pickedImageProvider(user.avatarUrl),
            child: user.avatarUrl.isEmpty
                ? Text(user.nickname.characters.firstOrNull ?? '?')
                : null,
          ),
          title: Text(user.nickname.isEmpty ? '未命名使用者' : user.nickname),
          subtitle: user.bio.isEmpty
              ? const Text('尚未填寫自我介紹')
              : Text(user.bio, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: onOpenProfile,
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'unfollow') onUnfollow();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'unfollow', child: Text('取消關注')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialAction {
  const _SocialAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _SocialActionGrid extends StatelessWidget {
  const _SocialActionGrid({required this.actions});

  final List<_SocialAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final entry in actions.indexed) ...[
          Expanded(
            child: CosCard(
              onTap: entry.$2.onTap,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CosIconBubble(
                    icon: entry.$2.icon,
                    color: switch (entry.$1) {
                      0 => scheme.primary,
                      1 => scheme.secondary,
                      _ => scheme.tertiary,
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    entry.$2.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.$2.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (entry.$1 != actions.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}
