import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/friendship.dart';
import '../../../core/models/partner_work.dart';
import '../../../core/models/same_work_user.dart';
import '../../../core/providers/friendship_providers.dart';
import '../../../core/providers/partner_discovery_providers.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/user_action.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'friendship_widgets.dart';

class PartnerDiscoveryPage extends StatelessWidget {
  const PartnerDiscoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tabHeight = MediaQuery.textScalerOf(context).scale(14) * 1.5 + 20;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(height: tabHeight, text: '與我同坑'),
              Tab(height: tabHeight, text: '看看大家坑什麼'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _PartnerWorksList(scope: PartnerWorkScope.mine),
                _PartnerWorksList(scope: PartnerWorkScope.all),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerWorksList extends ConsumerStatefulWidget {
  const _PartnerWorksList({required this.scope});
  final PartnerWorkScope scope;

  @override
  ConsumerState<_PartnerWorksList> createState() => _PartnerWorksListState();
}

class _PartnerWorksListState extends ConsumerState<_PartnerWorksList>
    with AutomaticKeepAliveClientMixin {
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = partnerWorksProvider((scope: widget.scope, q: _query));
    final works = ref.watch(provider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: ValueKey(widget.scope),
            maxLength: 100,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: '搜尋作品',
              hintText: '輸入作品名稱後搜尋',
              prefixIcon: Icon(Icons.search),
              counterText: '',
            ),
            onSubmitted: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: _DiscoveryResults<PartnerWork>(
            value: works,
            emptyTitle: _query.isNotEmpty
                ? '沒有符合搜尋的作品'
                : widget.scope == PartnerWorkScope.mine
                ? '你的坑單還沒有作品'
                : '目前沒有可探索的作品',
            onRetry: () => ref.invalidate(provider),
            onRefresh: () async {
              await runUserAction(context, () async {
                ref.invalidate(provider);
                await ref.read(provider.future);
              });
            },
            onLoadMore: () => ref.read(provider.notifier).loadMore(),
            itemBuilder: (work) => CosCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PartnerWorkPeoplePage(work: work),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text('${work.partnerCount} 位夥伴'),
                      if (work.isMine)
                        Text(
                          '我的坑',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PartnerWorkPeoplePage extends ConsumerWidget {
  const PartnerWorkPeoplePage({super.key, required this.work});
  final PartnerWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(partnerDiscoverySessionProvider);
    final provider = partnerWorkUsersProvider(work.id);
    final people = ref.watch(provider);
    final friends = ref.watch(friendshipsProvider);
    final friendshipReady =
        friends.hasValue && !friends.isLoading && !friends.hasError;
    return Scaffold(
      appBar: AppBar(
        title: Text(work.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          if (friends.hasError)
            TextButton.icon(
              onPressed: () => ref.invalidate(friendshipsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('重新讀取戳友狀態'),
            ),
          Expanded(
            child: _DiscoveryResults<SameWorkUser>(
              value: people,
              emptyTitle: '這部作品目前沒有可顯示的夥伴',
              onRetry: () => ref.invalidate(provider),
              onRefresh: () async {
                await runUserAction(context, () async {
                  ref.invalidate(provider);
                  ref.invalidate(friendshipsProvider);
                  await ref.read(provider.future);
                });
              },
              onLoadMore: () => ref.read(provider.notifier).loadMore(),
              itemBuilder: (user) => _PartnerPersonCard(
                user: user,
                relationship: friendshipReady
                    ? friends.asData?.value
                          .where((item) => item.userId == user.userId)
                          .firstOrNull
                    : null,
                friendshipReady: friendshipReady,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerPersonCard extends StatelessWidget {
  const _PartnerPersonCard({
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: pickedImageProvider(user.avatarUrl),
                child: user.avatarUrl.isEmpty
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.nickname,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(user.bio, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (user.commonWorkCount > 0) ...[
            const SizedBox(height: 8),
            Text('${user.commonWorkCount} 部共同作品'),
            if (user.commonWorks.isNotEmpty)
              Text(
                user.commonWorks.map((item) => item.name).join('、'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: user.publicCode.isEmpty ? null : openProfile,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('查看名片'),
              ),
              if (relationship?.isAccepted == true)
                const Text('已是戳友')
              else if (relationship?.isIncoming == true)
                TextButton(onPressed: openProfile, child: const Text('確認邀請'))
              else if (relationship != null)
                const Text('邀請已送出')
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

class _DiscoveryResults<T> extends StatelessWidget {
  const _DiscoveryResults({
    required this.value,
    required this.emptyTitle,
    required this.itemBuilder,
    required this.onRetry,
    required this.onRefresh,
    required this.onLoadMore,
  });
  final AsyncValue<PartnerDiscoveryData<T>> value;
  final String emptyTitle;
  final Widget Function(T) itemBuilder;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final children = value.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => <Widget>[
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        const Center(child: Text('載入中')),
      ],
      error: (error, _) => <Widget>[
        Text(userFacingError(error)),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('重試'),
        ),
      ],
      data: (page) => <Widget>[
        if (page.items.isEmpty) Text(emptyTitle),
        for (final item in page.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: itemBuilder(item),
          ),
        if (page.moreError != null) Text(userFacingError(page.moreError!)),
        if (page.nextOffset != null)
          OutlinedButton.icon(
            onPressed: page.loadingMore ? null : onLoadMore,
            icon: page.loadingMore
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: Text(
              page.loadingMore
                  ? '載入中'
                  : page.moreError != null
                  ? '重試載入更多'
                  : '載入更多',
            ),
          ),
      ],
    );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}
