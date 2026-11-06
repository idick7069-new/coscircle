import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/friendship.dart';
import '../../../core/models/same_work_user.dart';
import '../../../core/providers/friendship_providers.dart';
import '../../../core/providers/same_work_providers.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/user_action.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'friendship_widgets.dart';

class SameWorkList extends ConsumerStatefulWidget {
  const SameWorkList({super.key});

  @override
  ConsumerState<SameWorkList> createState() => _SameWorkListState();
}

class _SameWorkListState extends ConsumerState<SameWorkList> {
  bool _loadingMore = false;

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(sameWorkUsersProvider);
    final friends = ref.watch(friendshipsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await runUserAction(context, () async {
          ref.invalidate(sameWorkUsersProvider);
          await ref.read(sameWorkUsersProvider.future);
        });
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: users.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (error, _) => [
            Text(userFacingError(error)),
            TextButton.icon(
              onPressed: () => ref.invalidate(sameWorkUsersProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('重新整理'),
            ),
          ],
          data: (page) => [
            if (page.items.isEmpty)
              const CosCard(
                child: CosSectionHeader(
                  title: '尚未找到同坑的同好',
                  icon: Icons.auto_stories_outlined,
                ),
              ),
            for (final user in page.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SameWorkCard(
                  user: user,
                  relationship: friends.asData?.value
                      .where((item) => item.userId == user.userId)
                      .firstOrNull,
                  friendshipReady:
                      friends.hasValue &&
                      !friends.isLoading &&
                      !friends.hasError,
                ),
              ),
            if (friends.hasError && page.items.isNotEmpty)
              TextButton.icon(
                onPressed: () => ref.invalidate(friendshipsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('重新讀取戳友狀態'),
              ),
            if (page.nextOffset != null)
              OutlinedButton.icon(
                onPressed: _loadingMore
                    ? null
                    : () async {
                        setState(() => _loadingMore = true);
                        try {
                          await runUserAction(
                            context,
                            () => ref
                                .read(sameWorkUsersProvider.notifier)
                                .loadMore(),
                          );
                        } finally {
                          if (mounted) setState(() => _loadingMore = false);
                        }
                      },
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? '讀取中' : '載入更多'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SameWorkCard extends StatelessWidget {
  const _SameWorkCard({
    required this.user,
    required this.relationship,
    required this.friendshipReady,
  });
  final SameWorkUser user;
  final Friendship? relationship;
  final bool friendshipReady;

  @override
  Widget build(BuildContext context) {
    void openProfile() =>
        context.push('/profiles/${Uri.encodeComponent(user.publicCode)}');
    return CosCard(
      onTap: openProfile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: pickedImageProvider(user.avatarUrl),
                child: user.avatarUrl.isEmpty
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.nickname,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          const SizedBox(height: 12),
          CosBadge(
            label: '${user.commonWorkCount} 部同坑作品',
            icon: Icons.auto_stories_outlined,
            highlighted: true,
          ),
          const SizedBox(height: 8),
          Text(
            user.commonWorks.map((work) => work.name).join('、'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: openProfile,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('查看名片'),
              ),
              if (relationship?.isAccepted == true)
                const CosBadge(
                  label: '已是戳友',
                  icon: Icons.people_outline,
                  highlighted: true,
                )
              else if (relationship?.isIncoming == true)
                FilledButton.tonalIcon(
                  onPressed: openProfile,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('確認邀請'),
                )
              else if (relationship != null)
                const CosBadge(label: '邀請已送出', icon: Icons.schedule)
              else
                FilledButton.tonalIcon(
                  onPressed: !friendshipReady
                      ? null
                      : () => showDialog<bool>(
                          context: context,
                          builder: (_) =>
                              FriendInviteDialog(userId: user.userId),
                        ),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('戳友'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
