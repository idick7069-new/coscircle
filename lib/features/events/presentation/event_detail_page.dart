import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/models/event.dart';
import '../../../core/models/participant.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/event_day_display.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'event_booking_share_page.dart';

final eventDetailProvider = FutureProvider.autoDispose
    .family<CosEvent?, String>((ref, eventId) async {
      final events = await ref.watch(eventRepositoryProvider).fetchEvents();
      return events.where((item) => item.id == eventId).firstOrNull;
    });

class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventDetailProvider(eventId));
    final participants = ref.watch(eventParticipantsProvider(eventId));

    return AppPage(
      appBar: AppBar(
        title: const Text('活動詳細'),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: () {
              ref.invalidate(eventDetailProvider(eventId));
              ref.invalidate(eventParticipantsProvider(eventId));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      child: event.when(
        data: (value) {
          if (value == null) {
            return const Center(child: Text('找不到活動資料'));
          }
          return ListView(
            children: [
              _EventDetailHero(event: value),
              const SizedBox(height: 14),
              _InfoGrid(
                rows: [
                  _InfoRow.text('活動日期', _dateText(value)),
                  _InfoRow.text('活動地點', value.venue),
                  _InfoRow.text('詳細地址', value.detailedAddress),
                  _InfoRow.text('分類', value.category),
                  _InfoRow.text(
                    '狀態',
                    _statusText(value.status(DateTime.now())),
                  ),
                  _InfoRow.text('來源', value.sourceName),
                  _InfoRow.widget(
                    '原活動網址',
                    value.sourceUrl.isEmpty
                        ? const Text('未提供')
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EventSourceWebViewPage(
                                    title: value.name,
                                    url: value.sourceUrl,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_browser),
                              label: const Text('開啟原活動頁'),
                            ),
                          ),
                  ),
                  _InfoRow.text('費用', value.fee.isEmpty ? '未提供' : value.fee),
                  _InfoRow.text(
                    '主辦',
                    value.organizer.isEmpty ? '未提供' : value.organizer,
                  ),
                  _InfoRow.text('已加入', value.isJoined ? '是' : '否'),
                  _InfoRow.text(
                    '關注者參與',
                    value.hasFollowedParticipants ? '有' : '無',
                  ),
                  _InfoRow.text('小圈圈參與', value.hasCircleMembers ? '有' : '無'),
                ],
              ),
              const SizedBox(height: 16),
              CosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('活動說明', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      value.description.isEmpty ? '未提供活動說明' : value.description,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _ParticipantsSection(
                event: value,
                eventId: eventId,
                participants: participants,
              ),
            ],
          );
        },
        error: (error, stack) => _EventDetailStateCard(
          icon: Icons.wifi_off_outlined,
          title: '活動載入失敗',
          message: userFacingError(error),
          actionLabel: '重新整理',
          onAction: () => ref.invalidate(eventDetailProvider(eventId)),
        ),
        loading: () => const _EventDetailLoadingCard(),
      ),
    );
  }
}

class _EventDetailLoadingCard extends StatelessWidget {
  const _EventDetailLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const CosReveal(
      child: _EventDetailStateCard(
        icon: Icons.event_available_outlined,
        title: '正在整理活動訊號',
        message: '載入場次資訊、同好預定與現場交流線索。',
      ),
    );
  }
}

class _EventDetailStateCard extends StatelessWidget {
  const _EventDetailStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        CosGradientPanel(
          icon: icon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CosIconBubble(icon: icon, color: scheme.primary, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return CosCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(child: row.child),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventDetailHero extends StatelessWidget {
  const _EventDetailHero({required this.event});

  final CosEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageProvider = pickedImageProvider(event.imageUrl);
    final status = event.status(DateTime.now());
    return CosCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CosUi.radiusLg),
            ),
            child: AspectRatio(
              aspectRatio: 1.7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageProvider == null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer,
                            scheme.secondaryContainer,
                            scheme.tertiaryContainer,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.event_available_outlined,
                        color: scheme.primary,
                        size: 64,
                      ),
                    )
                  else
                    Image(
                      image: imageProvider,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.64),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CosBadge(
                          label: _statusText(status),
                          highlighted: status == EventStatus.active,
                          color: status == EventStatus.active
                              ? scheme.secondary
                              : scheme.tertiary,
                        ),
                        CosBadge(label: event.category, color: scheme.primary),
                        if (event.isJoined)
                          const CosBadge(
                            label: '已加入',
                            icon: Icons.check_circle,
                            highlighted: true,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventDisplayName(event),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMeta(
                        icon: Icons.calendar_month_outlined,
                        text: _dateText(event),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroMeta(
                        icon: Icons.place_outlined,
                        text: event.venue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CosIconBubble(icon: icon, size: 34),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _InfoRow {
  const _InfoRow._({required this.label, required this.child});

  factory _InfoRow.text(String label, String value) {
    return _InfoRow._(label: label, child: Text(value));
  }

  factory _InfoRow.widget(String label, Widget child) {
    return _InfoRow._(label: label, child: child);
  }

  final String label;
  final Widget child;
}

class EventSourceWebViewPage extends StatefulWidget {
  const EventSourceWebViewPage({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<EventSourceWebViewPage> createState() => _EventSourceWebViewPageState();
}

class _EventSourceWebViewPageState extends State<EventSourceWebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}

String _dateText(CosEvent event) {
  if (event.startDate == event.endDate) {
    return DateFormat('yyyy/MM/dd E', 'zh_TW').format(event.startDate);
  }
  return '${DateFormat('yyyy/MM/dd').format(event.startDate)} - ${DateFormat('yyyy/MM/dd').format(event.endDate)}';
}

String _statusText(EventStatus status) {
  return switch (status) {
    EventStatus.ended => '已結束',
    EventStatus.active => '正在進行',
    EventStatus.upcoming => '尚未到來',
  };
}

class _ParticipantsSection extends ConsumerWidget {
  const _ParticipantsSection({
    required this.event,
    required this.eventId,
    required this.participants,
  });

  final CosEvent event;
  final String eventId;
  final AsyncValue<List<EventParticipant>> participants;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return participants.when(
      data: (items) {
        final myBookings = items.where((item) => item.isMe).toList();
        final followedCount = items.where((item) => item.isFollowed).length;
        final circleSignals = items
            .where((item) => item.userId.isNotEmpty && !item.isMe)
            .length;
        final scheme = Theme.of(context).colorScheme;
        return CosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CosSectionHeader(
                title: '現場同好',
                subtitle: '看誰會去、要出什麼角色，先找到可以開話題的人',
                icon: Icons.diversity_3_outlined,
                trailing: CosBadge(
                  label: '${items.length} 位',
                  icon: Icons.people_outline,
                  highlighted: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CosMetricTile(
                      icon: Icons.person_pin_circle_outlined,
                      label: '關注者',
                      value: '$followedCount',
                      color: scheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CosMetricTile(
                      icon: Icons.badge_outlined,
                      label: '可查看名片',
                      value: '$circleSignals',
                      color: scheme.tertiary,
                    ),
                  ),
                ],
              ),
              if (myBookings.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EventBookingSharePage(
                            event: event,
                            bookings: myBookings,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('產生預訂分享圖'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (items.isEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(CosUi.radiusMd),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CosIconBubble(icon: Icons.person_search_outlined),
                        SizedBox(width: 12),
                        Expanded(child: Text('目前還沒有人公開預訂，加入後你會成為第一個訊號。')),
                      ],
                    ),
                  ),
                ),
              if (items.isNotEmpty)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final participant in items)
                      _ParticipantAvatar(
                        participant: participant,
                        onTap: () =>
                            _showParticipantSheet(context, ref, participant),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
      error: (error, stack) => _ParticipantPanelMessage(
        icon: Icons.wifi_off_outlined,
        message: '參加者載入失敗：${userFacingError(error)}',
      ),
      loading: () => const _ParticipantsLoadingPanel(),
    );
  }

  Future<void> _showParticipantSheet(
    BuildContext context,
    WidgetRef ref,
    EventParticipant participant,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: participantRoleColor(participant.role),
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage: pickedImageProvider(
                          participant.avatarUrl,
                        ),
                        child: participant.avatarUrl.isEmpty
                            ? Text(
                                participant.nickname.characters.firstOrNull ??
                                    '?',
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            participant.nickname,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(_roleText(participant)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (participant.message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(participant.message),
                ],
                if (participant.outfitImageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: pickedImageProvider(participant.outfitImageUrl)!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Text('當天出的角：${participant.outfitImageUrl}'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: participant.isMe
                            ? null
                            : () async {
                                if (participant.isFollowed) {
                                  await ref
                                      .read(eventRepositoryProvider)
                                      .unfollowUser(participant.userId);
                                } else {
                                  await ref
                                      .read(eventRepositoryProvider)
                                      .followUser(participant.userId);
                                }
                                ref.invalidate(
                                  eventParticipantsProvider(eventId),
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                        icon: Icon(
                          participant.isFollowed
                              ? Icons.person_remove
                              : Icons.person_add,
                        ),
                        label: Text(participant.isFollowed ? '取消關注' : '關注'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (participant.publicCode.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('尚未取得分享碼')),
                            );
                            return;
                          }
                          Navigator.of(context).pop();
                          context.push('/profiles/${participant.publicCode}');
                        },
                        icon: const Icon(Icons.info_outline),
                        label: const Text('詳細資料'),
                      ),
                    ),
                  ],
                ),
                if (!participant.isMe) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => CosSafetyConfirmDialog(
                            title: '封鎖 ${participant.nickname}？',
                            message: '封鎖後對方將看不到你的個人資訊、場次預定與現場訊號，也不能再關注你。',
                            actionLabel: '封鎖',
                            icon: Icons.block_outlined,
                            destructive: true,
                          ),
                        );
                        if (confirmed != true) return;
                        await ref
                            .read(eventRepositoryProvider)
                            .blockUser(participant.userId);
                        ref.invalidate(eventParticipantsProvider(eventId));
                        ref.invalidate(eventsProvider);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('已封鎖使用者')));
                      },
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('封鎖此使用者'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _roleText(EventParticipant participant) {
    final label = participantRoleLabel(participant.role);
    if (participant.role != 'coser') {
      return label;
    }
    final details = [
      if (participant.workName.isNotEmpty) participant.workName,
      if (participant.characterName.isNotEmpty) participant.characterName,
    ];
    if (details.isEmpty) return label;
    return '$label / ${details.join(' / ')}';
  }
}

class _ParticipantsLoadingPanel extends StatelessWidget {
  const _ParticipantsLoadingPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CosSectionHeader(
            title: '現場同好',
            subtitle: '正在整理同好預定與交流訊號',
            icon: Icons.diversity_3_outlined,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var index = 0; index < 3; index += 1) ...[
                _ParticipantSkeletonChip(color: scheme.primary),
                if (index < 2) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _ParticipantPanelMessage(
            icon: Icons.radar_outlined,
            message: '載入中，等等就能看到可開話題的人。',
          ),
        ],
      ),
    );
  }
}

class _ParticipantSkeletonChip extends StatelessWidget {
  const _ParticipantSkeletonChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const SizedBox(height: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantPanelMessage extends StatelessWidget {
  const _ParticipantPanelMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CosIconBubble(icon: icon, size: 34),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({required this.participant, required this.onTap});

  final EventParticipant participant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roleColor = participantRoleColor(participant.role);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 86,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: roleColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(CosUi.radiusMd),
            border: Border.all(color: roleColor.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: roleColor,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    backgroundImage: pickedImageProvider(participant.avatarUrl),
                    child: participant.avatarUrl.isEmpty
                        ? Text(
                            participant.nickname.characters.firstOrNull ?? '?',
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  participant.nickname,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  participantRoleLabel(participant.role),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
