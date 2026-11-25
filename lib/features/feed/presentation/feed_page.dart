import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/feed_post.dart';
import '../../../core/repositories/feed_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'feed_composer_page.dart';

const feedAudienceLabels = {
  'public': '公開',
  'friends': '戳友限定',
  'circle': '小圈圈限定',
};

Future<bool> feedConfirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認'),
          ),
        ],
      ),
    ) ??
    false;
void feedError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
}

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key, this.eventId, this.isVisible = true});
  final String? eventId;
  final bool isVisible;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(feedSessionProvider);
    return _FeedWall(
      key: ValueKey('$session-$eventId'),
      eventId: eventId,
      isVisible: isVisible,
    );
  }
}

class _FeedWall extends ConsumerStatefulWidget {
  const _FeedWall({super.key, this.eventId, required this.isVisible});
  final String? eventId;
  final bool isVisible;
  @override
  ConsumerState<_FeedWall> createState() => _FeedWallState();
}

class _FeedWallState extends ConsumerState<_FeedWall> {
  final _scroll = ScrollController();
  final List<FeedPost> _posts = [];
  String _kind = 'all', _scope = 'all';
  String? _next;
  bool _loading = true, _paging = false;
  Object? _error;
  bool _retryMore = false;
  int _generation = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && widget.isVisible) {
        ref.invalidate(feedNotificationsProvider);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _FeedWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      ref.invalidate(feedNotificationsProvider);
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 500 &&
        !_loading &&
        !_paging &&
        _next != null) {
      _load(more: true);
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_paging || _loading || _next == null)) return;
    final run = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _paging = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final result = await ref
          .read(feedRepositoryProvider)
          .list(
            kind: _kind,
            scope: _scope,
            eventId: widget.eventId,
            before: more ? _next : null,
          );
      if (!mounted || run != _generation) return;
      setState(() {
        if (!more) _posts.clear();
        final ids = _posts.map((p) => p.id).toSet();
        _posts.addAll(result.items.where((p) => !ids.contains(p.id)));
        _next = result.nextCursor;
        _error = null;
      });
    } catch (error) {
      if (mounted && run == _generation) {
        setState(() {
          _error = error;
          _retryMore = more;
        });
      }
    } finally {
      if (mounted && run == _generation) {
        setState(() {
          _loading = false;
          _paging = false;
        });
      }
    }
  }

  Future<void> _compose({required bool booking}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            FeedComposerPage(booking: booking, initialEventId: widget.eventId),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedRevisionProvider, (previous, next) {
      if (widget.isVisible) {
        _load();
      } else {
        setState(() {
          _posts.clear();
          _next = null;
          _loading = true;
        });
      }
    });
    final notifications = ref.watch(feedNotificationsProvider);
    final unread =
        notifications.asData?.value
            .where((n) => n['isRead'] == false || n['isRead'] == 0)
            .length ??
        0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
          child: CosPageHeader(
            title: widget.eventId == null ? '同坑動態' : '本場動態',
            subtitle: '場前發預定，場後繼續聊',
            leading: const CosIconBubble(icon: Icons.dynamic_feed_outlined),
            actions: [
              IconButton(
                tooltip: '互動通知',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FeedNotificationsPage(),
                  ),
                ),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              ),
              IconButton(
                tooltip: '重新整理動態',
                onPressed: () => _load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _compose(booking: true),
                  icon: const Icon(Icons.event_note),
                  label: const Text('分享預定'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _compose(booking: false),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('發貼文'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(
                    labelText: '內容',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('全部動態')),
                    DropdownMenuItem(value: 'booking', child: Text('預定')),
                    DropdownMenuItem(value: 'general', child: Text('一般貼文')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _kind = v);
                      _load();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _scope,
                  decoration: const InputDecoration(
                    labelText: '同好',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('看看大家')),
                    DropdownMenuItem(value: 'following', child: Text('關注與戳友')),
                    DropdownMenuItem(value: 'same-work', child: Text('與我同坑')),
                    DropdownMenuItem(value: 'circles', child: Text('小圈圈')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _scope = v);
                      _load();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: _loading
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: _posts.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _posts.length) {
                        if (_error != null) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(userFacingError(_error!)),
                                TextButton(
                                  onPressed: () => _load(more: _retryMore),
                                  child: const Text('重試'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (_paging) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (_posts.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Column(
                              children: [
                                Icon(Icons.forum_outlined, size: 48),
                                SizedBox(height: 12),
                                Text('這裡還沒有動態'),
                                Text(
                                  '分享下一場預定，讓同坑夥伴找到你。',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox(height: 16);
                      }
                      final post = _posts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FeedPostCard(
                          post: post,
                          onChanged: () => _load(),
                          onOpen: () async {
                            await context.push('/feed/${post.id}');
                            if (mounted) _load();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class FeedPostCard extends ConsumerStatefulWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpen,
  });
  final FeedPost post;
  final VoidCallback? onChanged, onOpen;
  @override
  ConsumerState<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<FeedPostCard> {
  bool _busy = false;
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) widget.onChanged?.call();
    } catch (e) {
      if (mounted) feedError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post, scheme = Theme.of(context).colorScheme;
    final profile = p.data.containsKey('isMe')
        ? null
        : ref.watch(_feedOwnProfileProvider).asData?.value;
    final mine = p.flag('isMe') || profile?.id == p.authorId;
    final image = p.isBooking ? p.text('outfitImageUrl') : '';
    final images = [if (image.isNotEmpty && !p.cancelled) image, ...p.images];
    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: p.publicCode.isEmpty
                    ? null
                    : () => context.push('/profiles/${p.publicCode}'),
                child: CircleAvatar(
                  backgroundImage: p.avatarUrl.isEmpty
                      ? null
                      : pickedImageProvider(p.avatarUrl),
                  child: p.avatarUrl.isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/profiles/${p.publicCode}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.nickname,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        feedAudienceLabels[p.visibility] ?? '',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '貼文選項',
                enabled: !_busy,
                onSelected: (value) async {
                  if (value == 'report') {
                    await showFeedReport(context, ref, p.id);
                    return;
                  }
                  if (value == 'edit') {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FeedComposerPage(existing: p),
                      ),
                    );
                    if (changed == true) widget.onChanged?.call();
                    return;
                  }
                  if (value == 'comments') {
                    await _action(
                      () => ref.read(feedRepositoryProvider).save({
                        ...p.toEditJson(),
                        'commentsEnabled': !p.commentsEnabled,
                      }, id: p.id),
                    );
                    return;
                  }
                  if (value == 'delete' &&
                      await feedConfirm(context, '刪除這篇貼文？')) {
                    await _action(
                      () => ref.read(feedRepositoryProvider).remove(p.id),
                    );
                  }
                },
                itemBuilder: (_) => [
                  if (mine) ...[
                    const PopupMenuItem(value: 'edit', child: Text('編輯貼文')),
                    PopupMenuItem(
                      value: 'comments',
                      child: Text(p.commentsEnabled ? '關閉留言' : '開啟留言'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('刪除貼文')),
                  ] else
                    const PopupMenuItem(value: 'report', child: Text('檢舉貼文')),
                ],
              ),
            ],
          ),
          if (p.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: InkWell(onTap: widget.onOpen, child: Text(p.body)),
            ),
          if (p.isBooking)
            InkWell(
              onTap: p.text('eventId').isEmpty
                  ? null
                  : () => context.push('/events/${p.text('eventId')}'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: p.cancelled
                      ? scheme.surfaceContainerHighest
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.cancelled ? '已取消預定' : '場次預定',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      p.text('eventName'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${p.text('eventDate')} · D${p.text('dayIndex')}'),
                    if (!p.cancelled)
                      Text(
                        [
                          p.text('workName'),
                          p.text('characterName'),
                          _roleLabels[p.text('role')] ?? '',
                        ].where((v) => v.isNotEmpty).join(' · '),
                      ),
                  ],
                ),
              ),
            ),
          if (!p.isBooking && p.text('eventName').isNotEmpty)
            TextButton.icon(
              onPressed: () => context.push('/events/${p.text('eventId')}'),
              icon: const Icon(Icons.event_outlined),
              label: Text(p.text('eventName')),
            ),
          if (p.text('workName').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Chip(
                avatar: Icon(p.sameWork ? Icons.radar : Icons.tag, size: 18),
                backgroundColor: p.sameWork ? scheme.tertiaryContainer : null,
                label: Text(
                  '${p.sameWork ? '跟你同坑 · ' : ''}${p.text('workName')}',
                ),
              ),
            ),
          if (images.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final url in images)
                  Builder(
                    builder: (context) {
                      final width =
                          (MediaQuery.sizeOf(context).width - 76)
                              .clamp(100, 520)
                              .toDouble() /
                          (images.length == 1 ? 1 : 2);
                      return InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            child: Stack(
                              children: [
                                InteractiveViewer(
                                  child: Image(
                                    image: pickedImageProvider(url)!,
                                    errorBuilder: (_, e, st) => const SizedBox(
                                      height: 120,
                                      child: Center(child: Text('圖片已無法顯示')),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    tooltip: '關閉圖片',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image(
                            image: pickedImageProvider(url)!,
                            width: width,
                            height: images.length == 1 ? 220 : 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, st) => SizedBox(
                              width: width,
                              height: 120,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _action(
                        () => ref
                            .read(feedRepositoryProvider)
                            .like(p.id, !p.liked),
                      ),
                icon: Icon(
                  p.liked ? Icons.favorite : Icons.favorite_border,
                  color: p.liked ? scheme.primary : null,
                ),
                label: Text('${p.count('likeCount')}'),
              ),
              TextButton.icon(
                onPressed: widget.onOpen,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text('${p.count('commentCount')} 留言'),
              ),
              if (!p.commentsEnabled) const Text('留言已關閉'),
            ],
          ),
        ],
      ),
    );
  }
}

const _roleLabels = {
  'coser': 'Coser',
  'photographer': '攝影',
  'manager': '馬內',
  'self': '同好',
};
final _feedOwnProfileProvider = FutureProvider.autoDispose((ref) {
  ref.watch(feedSessionProvider);
  return ref.watch(profileRepositoryProvider).currentProfile();
});

class FeedDetailPage extends ConsumerStatefulWidget {
  const FeedDetailPage({super.key, required this.postId});
  final String postId;
  @override
  ConsumerState<FeedDetailPage> createState() => _FeedDetailPageState();
}

class _FeedDetailPageState extends ConsumerState<FeedDetailPage> {
  final _text = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];
  Map<String, dynamic>? _reply;
  String? _next;
  bool _loading = true, _sending = false, _more = false;
  Object? _error, _sendError;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && _more) return;
    final run = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final data = await ref
          .read(feedRepositoryProvider)
          .comments(widget.postId, before: more ? _next : null);
      if (!mounted || run != _generation) return;
      setState(() {
        if (!more) _comments.clear();
        _comments.addAll(
          (data['items'] as List).map(
            (x) => Map<String, dynamic>.from(x as Map),
          ),
        );
        _next = data['nextCursor']?.toString();
      });
    } catch (e) {
      if (mounted && run == _generation) setState(() => _error = e);
    } finally {
      if (mounted && run == _generation) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(feedRepositoryProvider)
          .comment(
            widget.postId,
            _text.text.trim(),
            parentId: _reply?['id']?.toString(),
          );
      if (!mounted) return;
      _text.clear();
      setState(() => _reply = null);
      ref.invalidate(feedPostProvider(widget.postId));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _sendError = e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedRevisionProvider, (previous, next) => _load());
    ref.listen(feedSessionProvider, (previous, next) {
      _text.clear();
      _reply = null;
      _sendError = null;
      _comments.clear();
      _load();
    });
    final post = ref.watch(feedPostProvider(widget.postId)),
        me = ref.watch(_feedOwnProfileProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('貼文與留言')),
      body: post.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(userFacingError(e)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(feedPostProvider(widget.postId)),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
        data: (p) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(feedPostProvider(widget.postId));
                  await _load();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FeedPostCard(
                      post: p,
                      onChanged: () {
                        ref.invalidate(feedPostProvider(widget.postId));
                        _load();
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('留言', style: Theme.of(context).textTheme.titleMedium),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                    if (_error != null)
                      TextButton(
                        onPressed: () => _load(),
                        child: Text('載入留言失敗，點此重試：${userFacingError(_error!)}'),
                      ),
                    if (!_loading && _comments.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('還沒有留言，來打聲招呼吧。'),
                      ),
                    for (final c in _comments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: InkWell(
                          onTap: () =>
                              context.push('/profiles/${c['publicCode']}'),
                          child: CircleAvatar(
                            backgroundImage:
                                (c['avatarUrl']?.toString() ?? '').isEmpty
                                ? null
                                : pickedImageProvider(
                                    c['avatarUrl'].toString(),
                                  ),
                            child: (c['avatarUrl']?.toString() ?? '').isEmpty
                                ? const Icon(Icons.person_outline)
                                : null,
                          ),
                        ),
                        title: InkWell(
                          onTap: () =>
                              context.push('/profiles/${c['publicCode']}'),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(c['nickname']?.toString() ?? ''),
                              if (c['authorId']?.toString() == p.authorId)
                                Tooltip(
                                  message: '貼文作者（原 PO）',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_note_outlined,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '原 PO',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c['parentId'] != null)
                              Text(
                                '回覆 ${c['replyTo'] ?? '已隱藏的留言'}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            Text(c['body']?.toString() ?? ''),
                            if (p.commentsEnabled)
                              TextButton(
                                onPressed: _sending
                                    ? null
                                    : () {
                                        setState(() => _reply = c);
                                      },
                                child: const Text('回覆'),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: '留言選項',
                          onSelected: (v) async {
                            if (v == 'report') {
                              await showFeedReport(
                                context,
                                ref,
                                p.id,
                                commentId: c['id'].toString(),
                              );
                              return;
                            }
                            if (await feedConfirm(context, '刪除這則留言？')) {
                              try {
                                await ref
                                    .read(feedRepositoryProvider)
                                    .removeComment(p.id, c['id'].toString());
                                if (mounted) {
                                  await _load();
                                  ref.invalidate(feedPostProvider(p.id));
                                }
                              } catch (e) {
                                if (context.mounted) feedError(context, e);
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            if (p.flag('isMe') ||
                                c['isMe'] == true ||
                                c['isMe'] == 1 ||
                                me?.id == p.authorId ||
                                me?.id == c['authorId']?.toString())
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('刪除留言'),
                              ),
                            if (c['isMe'] != true &&
                                c['isMe'] != 1 &&
                                me?.id != c['authorId']?.toString())
                              const PopupMenuItem(
                                value: 'report',
                                child: Text('檢舉留言'),
                              ),
                          ],
                        ),
                      ),
                    if (_next != null)
                      TextButton(
                        onPressed: _more ? null : () => _load(more: true),
                        child: Text(_more ? '載入中…' : '載入較早的留言'),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_sendError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          userFacingError(_sendError!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_reply != null)
                      Row(
                        children: [
                          Expanded(child: Text('回覆 ${_reply!['nickname']}')),
                          IconButton(
                            tooltip: '取消回覆',
                            onPressed: _sending
                                ? null
                                : () => setState(() => _reply = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    if (p.commentsEnabled)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              onChanged: (_) => setState(() {}),
                              enabled: !_sending,
                              maxLength: 1000,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: '留下想說的話',
                                counterText: '',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '送出留言',
                            onPressed: _sending || _text.text.trim().isEmpty
                                ? null
                                : _send,
                            icon: _sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
                      )
                    else
                      const Text('作者已關閉留言'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFeedReport(
  BuildContext context,
  WidgetRef ref,
  String postId, {
  String? commentId,
}) async {
  final input = await showDialog<({String reason, String details})>(
    context: context,
    builder: (_) => const _FeedReportDialog(),
  );
  if (input == null || !context.mounted) return;
  try {
    await ref
        .read(feedRepositoryProvider)
        .report(
          postId,
          reason: input.reason,
          details: input.details,
          commentId: commentId,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已收到檢舉，管理員將進行審查。')));
    }
  } catch (e) {
    if (context.mounted) feedError(context, e);
  }
}

class _FeedReportDialog extends StatefulWidget {
  const _FeedReportDialog();
  @override
  State<_FeedReportDialog> createState() => _FeedReportDialogState();
}

class _FeedReportDialogState extends State<_FeedReportDialog> {
  final _details = TextEditingController();
  String _reason = 'harassment';
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('檢舉內容'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reason,
            items: const [
              DropdownMenuItem(value: 'harassment', child: Text('騷擾或霸凌')),
              DropdownMenuItem(
                value: 'sexual_content',
                child: Text('色情或兒少安全問題'),
              ),
              DropdownMenuItem(value: 'privacy', child: Text('隱私侵害')),
              DropdownMenuItem(value: 'spam', child: Text('垃圾訊息或廣告')),
              DropdownMenuItem(value: 'hate', child: Text('仇恨或歧視')),
              DropdownMenuItem(value: 'impersonation', child: Text('冒用身分')),
              DropdownMenuItem(value: 'other', child: Text('其他')),
            ],
            onChanged: (v) {
              if (v != null) _reason = v;
            },
          ),
          TextField(
            controller: _details,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '補充說明（選填）'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (reason: _reason, details: _details.text)),
        child: const Text('送出檢舉'),
      ),
    ],
  );
}

class FeedNotificationsPage extends ConsumerWidget {
  const FeedNotificationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(feedNotificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('互動通知')),
      body: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(feedNotificationsProvider),
            child: Text('重新載入：${userFacingError(e)}'),
          ),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(feedNotificationsProvider);
            await ref.read(feedNotificationsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('還沒有新的互動通知', textAlign: TextAlign.center),
                ),
              for (final n in rows)
                ListTile(
                  leading: Icon(
                    n['kind'] == 'like'
                        ? Icons.favorite_outline
                        : Icons.chat_bubble_outline,
                  ),
                  title: Text(
                    n['kind'] == 'like'
                        ? '你的貼文收到喜歡'
                        : n['kind'] == 'reply'
                        ? '你的留言有新回覆'
                        : '你的貼文有新留言',
                  ),
                  subtitle: const Text('點擊查看貼文'),
                  trailing: n['isRead'] == true || n['isRead'] == 1
                      ? null
                      : const Badge(),
                  onTap: () async {
                    try {
                      await ref
                          .read(feedRepositoryProvider)
                          .readNotification(n['id'].toString());
                      ref.invalidate(feedNotificationsProvider);
                      if (context.mounted) context.push('/feed/${n['postId']}');
                    } catch (e) {
                      if (context.mounted) feedError(context, e);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
