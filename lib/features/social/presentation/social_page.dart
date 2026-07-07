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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: _SocialSignalOverview(
              circles: circles,
              following: following,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(CosUi.radiusLg),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                boxShadow: [
                  CosUi.softShadow(Theme.of(context).colorScheme.shadow),
                ],
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(CosUi.radiusMd),
                ),
                labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant,
                labelStyle: Theme.of(context).textTheme.labelLarge,
                padding: const EdgeInsets.all(6),
                tabs: const [
                  Tab(text: '小圈圈', icon: Icon(Icons.groups_outlined)),
                  Tab(text: '已關注', icon: Icon(Icons.favorite_border)),
                ],
              ),
            ),
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
                              for (final entry in items.indexed)
                                CosReveal(
                                  delay: Duration(milliseconds: 45 * entry.$1),
                                  child: _CircleCard(
                                    circle: entry.$2,
                                    onLeave: () =>
                                        _confirmLeave(context, ref, entry.$2),
                                    onEdit: entry.$2.isOwner
                                        ? () => _editCircle(
                                            context,
                                            ref,
                                            entry.$2,
                                          )
                                        : null,
                                    onOpenMember: (member) {
                                      if (member.publicCode.isEmpty) return;
                                      context.push(
                                        '/profiles/${member.publicCode}',
                                      );
                                    },
                                    onRemoveMember: entry.$2.isOwner
                                        ? (member) => _confirmRemoveMember(
                                            context,
                                            ref,
                                            entry.$2,
                                            member,
                                          )
                                        : null,
                                  ),
                                ),
                            ],
                          );
                        },
                        error: (error, stack) => _SocialErrorCard(
                          title: '小圈圈載入失敗',
                          message: userFacingError(error),
                          onRetry: () => ref.invalidate(circlesProvider),
                        ),
                        loading: () => const _SocialLoadingStack(
                          title: '正在整理小圈圈',
                          subtitle: '同步邀請碼、成員和聚會訊號',
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
                          for (final entry in items.indexed)
                            CosReveal(
                              delay: Duration(milliseconds: 45 * entry.$1),
                              child: _FollowedUserCard(
                                user: entry.$2,
                                onOpenProfile: () {
                                  if (entry.$2.publicCode.isEmpty) return;
                                  context.push(
                                    '/profiles/${entry.$2.publicCode}',
                                  );
                                },
                                onUnfollow: () =>
                                    _confirmUnfollow(context, ref, entry.$2),
                              ),
                            ),
                        ],
                      );
                    },
                    error: (error, stack) => ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SocialErrorCard(
                          title: '關注清單載入失敗',
                          message: userFacingError(error),
                          onRetry: () => ref.invalidate(followingProvider),
                        ),
                      ],
                    ),
                    loading: () => ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [
                        _SocialLoadingStack(
                          title: '正在整理關注名單',
                          subtitle: '把活動現場最重要的同好排好',
                        ),
                      ],
                    ),
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
      builder: (context) => CosSafetyConfirmDialog(
        icon: Icons.favorite_border,
        title: '取消關注',
        message: '確定要取消關注「${user.nickname}」？之後活動現場就不會優先顯示這位同好。',
        cancelLabel: '保留',
        actionLabel: '取消關注',
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
      builder: (context) => CosSafetyConfirmDialog(
        icon: Icons.person_remove_outlined,
        title: '移除成員',
        message: '確定要將「${member.nickname}」移出「${circle.name}」？',
        cancelLabel: '保留',
        actionLabel: '移除',
        destructive: true,
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
      builder: (context) => CosSafetyConfirmDialog(
        icon: Icons.logout_outlined,
        title: '離開小圈圈',
        message: '確定要離開「${circle.name}」？離開後就不會收到這個小圈圈的集合訊號。',
        cancelLabel: '保留',
        actionLabel: '離開',
        destructive: true,
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
  bool _submitting = false;

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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      clipBehavior: Clip.antiAlias,
      child: CosGradientPanel(
        icon: create ? Icons.groups_2_outlined : Icons.qr_code_2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosSectionHeader(
              title: editing
                  ? '編輯小圈圈'
                  : create
                  ? '新建小圈圈'
                  : '加入小圈圈',
              subtitle: create ? '建立一個可以約場、集合和認親的同好群組' : '輸入朋友提供的邀請碼或網址',
              icon: create ? Icons.groups_2_outlined : Icons.qr_code_2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: create ? '小圈圈名稱' : '邀請碼或網址',
              ),
            ),
            if (create) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: '小圈圈說明'),
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting
                        ? null
                        : () async {
                            final value = _controller.text.trim();
                            if (value.isEmpty) return;
                            setState(() => _submitting = true);
                            final repository = ref.read(
                              socialRepositoryProvider,
                            );
                            try {
                              if (editing) {
                                await repository.updateCircle(
                                  circleId: widget.circle!.id,
                                  name: value,
                                  description: _descriptionController.text
                                      .trim(),
                                );
                              } else if (create) {
                                await repository.createCircle(
                                  value,
                                  description: _descriptionController.text
                                      .trim(),
                                );
                              } else {
                                await repository.joinCircle(value);
                              }
                              ref.invalidate(circlesProvider);
                              if (context.mounted) Navigator.pop(context);
                            } finally {
                              if (mounted) setState(() => _submitting = false);
                            }
                          },
                    icon: _submitting
                        ? CosLoadingPulse(
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 20,
                          )
                        : Icon(
                            editing
                                ? Icons.save_outlined
                                : create
                                ? Icons.group_add
                                : Icons.login,
                          ),
                    label: Text(
                      _submitting
                          ? '處理中'
                          : editing
                          ? '儲存'
                          : create
                          ? '建立'
                          : '加入',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

class _SocialSignalOverview extends StatelessWidget {
  const _SocialSignalOverview({required this.circles, required this.following});

  final AsyncValue<List<CircleGroup>> circles;
  final AsyncValue<List<FollowedUser>> following;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final circleCount = circles.whenOrNull(data: (items) => items.length);
    final memberCount = circles.whenOrNull(
      data: (items) =>
          items.fold<int>(0, (total, circle) => total + circle.members.length),
    );
    final followingCount = following.whenOrNull(data: (items) => items.length);

    return CosGradientPanel(
      icon: Icons.diversity_3_outlined,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CosIconBubble(
                icon: Icons.auto_awesome,
                color: scheme.primary,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '同好訊號',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '先整理小圈圈和關注名單，活動現場更快找到朋友。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _SocialSignalMetric(
                  icon: Icons.groups_outlined,
                  label: '小圈圈',
                  value: circleCount == null ? '同步中' : '$circleCount',
                  color: scheme.primary,
                ),
                _SocialSignalMetric(
                  icon: Icons.diversity_3_outlined,
                  label: '成員訊號',
                  value: memberCount == null ? '同步中' : '$memberCount',
                  color: scheme.secondary,
                ),
                _SocialSignalMetric(
                  icon: Icons.favorite_border,
                  label: '已關注',
                  value: followingCount == null ? '同步中' : '$followingCount',
                  color: scheme.tertiary,
                ),
              ];
              if (constraints.maxWidth < 360) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: metric,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (final metric in metrics) ...[
                    Expanded(child: metric),
                    if (metric != metrics.last) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SocialSignalMetric extends StatelessWidget {
  const _SocialSignalMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialErrorCard extends StatelessWidget {
  const _SocialErrorCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosIconBubble(icon: Icons.wifi_off_outlined, color: scheme.error),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試一次'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialLoadingStack extends StatelessWidget {
  const _SocialLoadingStack({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosSectionHeader(
            title: title,
            subtitle: subtitle,
            icon: Icons.radar_outlined,
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < 3; index += 1) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(CosUi.radiusMd),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          (index.isEven ? scheme.primary : scheme.secondary)
                              .withValues(alpha: 0.18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SocialSkeletonLine(
                            widthFactor: index == 0 ? 0.64 : 0.48,
                            height: 13,
                          ),
                          const SizedBox(height: 8),
                          _SocialSkeletonLine(
                            widthFactor: index == 1 ? 0.78 : 0.58,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index < 2) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SocialSkeletonLine extends StatelessWidget {
  const _SocialSkeletonLine({required this.widthFactor, this.height = 9});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: SizedBox(height: height),
      ),
    );
  }
}

class _CircleCard extends StatefulWidget {
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
  State<_CircleCard> createState() => _CircleCardState();
}

class _CircleCardState extends State<_CircleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final circle = widget.circle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CosCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CosUi.radiusLg),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          (circle.isOwner
                                  ? scheme.primaryContainer
                                  : scheme.secondaryContainer)
                              .withValues(alpha: _expanded ? 0.44 : 0.24),
                          scheme.surfaceContainerLowest,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        CosIconBubble(
                          icon: Icons.groups_2_outlined,
                          color: circle.isOwner
                              ? scheme.primary
                              : scheme.secondary,
                          size: 48,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      circle.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  if (circle.isOwner)
                                    CosBadge(
                                      label: '我建立的',
                                      icon: Icons.star_border_rounded,
                                      color: scheme.primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                circle.description.isEmpty
                                    ? '小圈圈集合點，適合約場、認親和交換作品'
                                    : circle.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _MemberAvatarStrip(members: circle.members),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${circle.memberCount} 位成員',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') widget.onEdit?.call();
                            if (value == 'leave') widget.onLeave();
                          },
                          itemBuilder: (context) => [
                            if (widget.onEdit != null)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('編輯'),
                              ),
                            const PopupMenuItem(
                              value: 'leave',
                              child: Text('離開'),
                            ),
                          ],
                        ),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            _CircleInviteBand(
                              circle: circle,
                              onShowQr: () => _showCircleQr(context),
                            ),
                            const SizedBox(height: 12),
                            for (final entry in circle.members.indexed)
                              CosReveal(
                                delay: Duration(milliseconds: 35 * entry.$1),
                                child: _CircleMemberRow(
                                  member: entry.$2,
                                  canRemove:
                                      circle.isOwner && !entry.$2.isOwner,
                                  onOpen: () => widget.onOpenMember(entry.$2),
                                  onRemove: () =>
                                      widget.onRemoveMember?.call(entry.$2),
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCircleQr(BuildContext context) {
    final circle = widget.circle;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.antiAlias,
        child: CosGradientPanel(
          icon: Icons.qr_code_2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CosSectionHeader(
                title: circle.name,
                subtitle: '讓同好掃描後加入這個小圈圈',
                icon: Icons.qr_code_2,
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(CosUi.radiusLg),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: QrImageView(
                    data: circle.inviteUrl.isEmpty
                        ? circle.inviteCode
                        : circle.inviteUrl,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CosBadge(
                label: circle.inviteCode,
                icon: Icons.vpn_key_outlined,
                highlighted: true,
              ),
              const SizedBox(height: 12),
              SelectableText(
                circle.inviteUrl.isEmpty ? circle.inviteCode : circle.inviteUrl,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleMemberRow extends StatelessWidget {
  const _CircleMemberRow({
    required this.member,
    required this.canRemove,
    required this.onOpen,
    required this.onRemove,
  });

  final CircleMember member;
  final bool canRemove;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nickname = member.nickname.isEmpty ? '未命名使用者' : member.nickname;
    final initial = nickname.characters.firstOrNull ?? '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: member.isOwner
                        ? scheme.primaryContainer
                        : scheme.secondaryContainer,
                    backgroundImage: pickedImageProvider(member.avatarUrl),
                    child: member.avatarUrl.isEmpty
                        ? Text(
                            initial,
                            style: TextStyle(
                              color: member.isOwner
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        CosBadge(
                          label: member.isOwner ? '建立者' : '同好成員',
                          icon: member.isOwner
                              ? Icons.auto_awesome
                              : Icons.handshake_outlined,
                          color: member.isOwner
                              ? scheme.primary
                              : scheme.secondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (canRemove)
                    IconButton(
                      tooltip: '移除成員',
                      onPressed: onRemove,
                      icon: const Icon(Icons.person_remove_outlined),
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleInviteBand extends StatelessWidget {
  const _CircleInviteBand({required this.circle, required this.onShowQr});

  final CircleGroup circle;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.62),
            scheme.secondaryContainer.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CosIconBubble(
              icon: Icons.qr_code_2,
              color: scheme.primary,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CosBadge(
                        label: circle.inviteCode,
                        icon: Icons.vpn_key_outlined,
                        highlighted: true,
                      ),
                      Text(
                        '邀請碼',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  if (circle.inviteUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      circle.inviteUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '顯示邀請 QRCode',
              onPressed: onShowQr,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
    final nickname = user.nickname.isEmpty ? '未命名使用者' : user.nickname;
    final initial = nickname.characters.firstOrNull ?? '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CosCard(
        onTap: onOpenProfile,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: pickedImageProvider(user.avatarUrl),
                  child: user.avatarUrl.isEmpty
                      ? Text(
                          initial,
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.favorite,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CosBadge(
                        label: '已關注',
                        icon: Icons.favorite_border,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.bio.isEmpty ? '尚未填寫自我介紹，現場掃碼後可以快速認親。' : user.bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '更多同好操作',
              onSelected: (value) {
                if (value == 'unfollow') onUnfollow();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'unfollow', child: Text('取消關注')),
              ],
            ),
          ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          for (final entry in actions.indexed)
            CosReveal(
              delay: Duration(milliseconds: 35 * entry.$1),
              child: _SocialActionCard(
                action: entry.$2,
                color: switch (entry.$1) {
                  0 => scheme.primary,
                  1 => scheme.secondary,
                  _ => scheme.tertiary,
                },
              ),
            ),
        ];
        if (constraints.maxWidth < 360) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final card in cards)
                SizedBox(width: (constraints.maxWidth - 10) / 2, child: card),
            ],
          );
        }
        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _SocialActionCard extends StatelessWidget {
  const _SocialActionCard({required this.action, required this.color});

  final _SocialAction action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CosCard(
      onTap: action.onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosIconBubble(icon: action.icon, color: color),
          const SizedBox(height: 12),
          Text(
            action.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            action.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
