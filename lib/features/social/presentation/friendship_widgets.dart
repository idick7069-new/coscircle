import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/event_day_item.dart';
import '../../../core/models/friendship.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/providers/friendship_providers.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/repositories/location_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/user_action.dart';
import '../../../shared/widgets/cos_ui.dart';

void refreshFriendships(WidgetRef ref) {
  ref.invalidate(friendshipsProvider);
  ref.invalidate(eventsProvider);
  ref.invalidate(eventParticipantsProvider);
  ref.invalidate(locationRepositoryProvider);
}

class FriendshipList extends ConsumerWidget {
  const FriendshipList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendships = ref.watch(friendshipsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(friendshipsProvider);
        await ref.read(friendshipsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: friendships.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (error, stack) => [
            Text(userFacingError(error)),
            TextButton.icon(
              onPressed: () => ref.invalidate(friendshipsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('重新整理'),
            ),
          ],
          data: (items) => [
            for (final group in const [
              ('incoming', '收到的邀請'),
              ('accepted', '戳友'),
              ('pending', '已送出的邀請'),
            ]) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  group.$2,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!items.any((item) => item.status == group.$1))
                Text(
                  group.$1 == 'incoming'
                      ? '目前沒有新邀請'
                      : group.$1 == 'accepted'
                      ? '目前沒有戳友'
                      : '目前沒有送出的邀請',
                ),
              for (final item in items.where((item) => item.status == group.$1))
                FriendshipTile(
                  friendship: item,
                  onOpen: item.publicCode.isEmpty
                      ? null
                      : () => context.push('/profiles/${item.publicCode}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class FriendshipTile extends ConsumerStatefulWidget {
  const FriendshipTile({super.key, required this.friendship, this.onOpen});
  final Friendship friendship;
  final VoidCallback? onOpen;
  @override
  ConsumerState<FriendshipTile> createState() => _FriendshipTileState();
}

class _FriendshipTileState extends ConsumerState<FriendshipTile> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    final succeeded = await runUserAction(
      context,
      () => ref
          .read(socialRepositoryProvider)
          .respondFriend(widget.friendship.id, accept: accept),
    );
    if (!mounted) return;
    if (succeeded) refreshFriendships(ref);
    setState(() => _busy = false);
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const CosSafetyConfirmDialog(
        title: '解除戳友？',
        message: '原有的關注與小圈圈不會受到影響。',
        actionLabel: '解除',
        icon: Icons.person_remove_outlined,
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final succeeded = await runUserAction(
      context,
      () => ref
          .read(socialRepositoryProvider)
          .removeFriend(widget.friendship.userId),
    );
    if (!mounted) return;
    if (succeeded) refreshFriendships(ref);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.friendship;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CosCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: pickedImageProvider(item.avatarUrl),
                  child: item.avatarUrl.isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: widget.onOpen,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.nickname,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                if (item.isAccepted)
                  IconButton(
                    tooltip: '解除戳友',
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
              ],
            ),
            Text(item.eventLabel),
            const SizedBox(height: 8),
            Text(
              item.introductionIsMine ? '你當時的介紹' : '對方當時的介紹',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(item.introduction),
            if (item.isIncoming) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _respond(true),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('確認戳友'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _respond(false),
                    child: const Text('忽略'),
                  ),
                ],
              ),
            ] else if (!item.isAccepted) ...[
              const SizedBox(height: 8),
              const Text('等待確認'),
            ],
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class ProfileFriendshipActions extends ConsumerStatefulWidget {
  const ProfileFriendshipActions({
    super.key,
    required this.userId,
    required this.requireLogin,
    this.eventId,
    this.dayIndex,
  });
  final String userId;
  final Future<bool> Function() requireLogin;
  final String? eventId;
  final int? dayIndex;
  @override
  ConsumerState<ProfileFriendshipActions> createState() =>
      _ProfileFriendshipActionsState();
}

class _ProfileFriendshipActionsState
    extends ConsumerState<ProfileFriendshipActions> {
  bool _authenticated = false;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    _loadAuthentication();
  }

  Future<void> _loadAuthentication() async {
    final token = (await SharedPreferences.getInstance()).getString(
      'auth_token',
    );
    if (mounted) {
      setState(() {
        _loaded = true;
        _authenticated = token != null && token.isNotEmpty;
      });
    }
  }

  Future<void> _invite() async {
    if (!await widget.requireLogin() || !mounted) return;
    await showDialog<bool>(
      context: context,
      builder: (context) => FriendInviteDialog(
        userId: widget.userId,
        eventId: widget.eventId,
        dayIndex: widget.dayIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    if (!_authenticated) return _inviteButton();
    return ref
        .watch(friendshipsProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Column(
            children: [
              Text(userFacingError(error)),
              TextButton.icon(
                onPressed: () => ref.invalidate(friendshipsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('重新整理戳友狀態'),
              ),
            ],
          ),
          data: (items) {
            final item = items
                .where((item) => item.userId == widget.userId)
                .firstOrNull;
            return item == null
                ? _inviteButton()
                : FriendshipTile(friendship: item);
          },
        );
  }

  Widget _inviteButton() => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.tonalIcon(
      onPressed: _invite,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('戳友'),
    ),
  );
}

class FriendInviteDialog extends ConsumerStatefulWidget {
  const FriendInviteDialog({
    super.key,
    required this.userId,
    this.eventId,
    this.dayIndex,
  });
  final String userId;
  final String? eventId;
  final int? dayIndex;
  @override
  ConsumerState<FriendInviteDialog> createState() => _FriendInviteDialogState();
}

class _FriendInviteDialogState extends ConsumerState<FriendInviteDialog> {
  final _introduction = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _eventKey;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.eventId != null && widget.dayIndex != null) {
      _eventKey = '${widget.eventId}:${widget.dayIndex}';
    }
  }

  @override
  void dispose() {
    _introduction.dispose();
    super.dispose();
  }

  Future<void> _send(List<EventDayItem> days) async {
    if (!_formKey.currentState!.validate() || _busy) return;
    final day = days.where((day) => day.id == _eventKey).firstOrNull;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref
          .read(socialRepositoryProvider)
          .inviteFriend(
            widget.userId,
            introduction: _introduction.text.trim(),
            eventId: day?.event.id,
            dayIndex: day?.dayIndex,
          );
      if (!mounted) return;
      refreshFriendships(ref);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'incoming'
                ? '對方也已送出邀請，請確認戳友'
                : status == 'accepted'
                ? '你們已經是戳友'
                : '已送出戳友邀請',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = userFacingError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final days = expandEventDays(events.asData?.value ?? []);
    final selected = days.any((day) => day.id == _eventKey) ? _eventKey : null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('戳友邀請'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _introduction,
                    enabled: !_busy,
                    maxLength: 200,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '簡短自我介紹',
                      hintText: '我是戴黑色帽子在水池旁拍照的攝影',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '請留下方便辨認的介紹'
                        : value.trim().runes.length > 200
                        ? '介紹不可超過 200 字'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '認識的場次'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('未指定場次')),
                      for (final day in days)
                        DropdownMenuItem(
                          value: day.id,
                          child: Text(
                            '${day.title} · ${DateFormat('yyyy/MM/dd').format(day.date)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _eventKey = value),
                  ),
                  if (events.isLoading) const LinearProgressIndicator(),
                  if (events.hasError)
                    TextButton.icon(
                      onPressed: () => ref.invalidate(eventsProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('場次載入失敗，重試'),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: _busy || events.isLoading || events.hasError
                ? null
                : () => _send(days),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('送出邀請'),
          ),
        ],
      ),
    );
  }
}
