import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/event.dart';
import '../../../core/models/participant.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/utils/event_day_display.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'event_booking_share_page.dart';
import 'event_list_page.dart';

class MyEventsPage extends ConsumerStatefulWidget {
  const MyEventsPage({super.key});

  @override
  ConsumerState<MyEventsPage> createState() => _MyEventsPageState();
}

class _MyEventsPageState extends ConsumerState<MyEventsPage> {
  bool _showEnded = false;
  late Future<List<_MyBookingItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadMyBookings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的活動')),
      body: SafeArea(
        child: FutureBuilder<List<_MyBookingItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const _MyEventsLoadingState();
            }
            final allItems = snapshot.data!..sort(_compareBookingItems);
            final visibleItems = allItems
                .where((item) => _showEnded || !item.isEnded)
                .toList();
            final activeItems = allItems.where((item) => !item.isEnded).length;
            final shareReadyItems = allItems
                .where((item) => item.participant.outfitImageUrl.isNotEmpty)
                .length;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CosPageHeader(
                    title: '我的活動',
                    subtitle: '整理已加入場次、出角預訂與分享卡',
                    leading: const CosIconBubble(
                      icon: Icons.event_available_outlined,
                    ),
                    actions: [
                      CosChoicePill(
                        label: '顯示已過期',
                        selected: _showEnded,
                        icon: Icons.history_toggle_off_outlined,
                        onTap: () => setState(() => _showEnded = !_showEnded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CosReveal(
                    child: CosGradientPanel(
                      icon: Icons.confirmation_number_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CosSectionHeader(
                            title: '我的參戰票夾',
                            subtitle: '整理即將出席的場次、角色名片與分享圖素材',
                            icon: Icons.wallet_outlined,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: CosMetricTile(
                                  icon: Icons.event_available_outlined,
                                  label: '未來場次',
                                  value: '$activeItems',
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CosMetricTile(
                                  icon: Icons.badge_outlined,
                                  label: '預訂名片',
                                  value: '${allItems.length}',
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CosMetricTile(
                                  icon: Icons.image_outlined,
                                  label: '可產圖',
                                  value: '$shareReadyItems',
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (visibleItems.isEmpty)
                    const _MyEventsEmptyState()
                  else
                    for (final entry in visibleItems.indexed) ...[
                      CosReveal(
                        delay: Duration(milliseconds: 55 * entry.$1),
                        offset: const Offset(0, 10),
                        child: _MyBookingCard(
                          item: entry.$2,
                          onEdit: () => _editBooking(entry.$2),
                          onCancel: () => _cancelBooking(entry.$2),
                          onShare: () => _shareBooking(entry.$2, allItems),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<List<_MyBookingItem>> _loadMyBookings() async {
    final events = await ref.read(eventsProvider.future);
    final joinedEvents = events.where((event) => event.isJoined).toList();
    final rows = <_MyBookingItem>[];
    for (final event in joinedEvents) {
      final participants = await ref
          .read(eventRepositoryProvider)
          .fetchParticipants(event.id);
      for (final participant in participants.where((item) => item.isMe)) {
        rows.add(_MyBookingItem(event: event, participant: participant));
      }
    }
    return rows;
  }

  int _compareBookingItems(_MyBookingItem a, _MyBookingItem b) {
    if (a.isEnded != b.isEnded) return a.isEnded ? 1 : -1;
    return a.date.compareTo(b.date);
  }

  Future<void> _refresh() async {
    ref.invalidate(eventParticipantsProvider);
    final _ = await ref.refresh(eventsProvider.future);
    setState(() => _itemsFuture = _loadMyBookings());
  }

  Future<void> _editBooking(_MyBookingItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => BookingSheet(
        event: item.event,
        initialDayIndex: item.participant.dayIndex,
        initialParticipant: item.participant,
      ),
    );
    await _refresh();
  }

  Future<void> _cancelBooking(_MyBookingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _CancelBookingDialog(item: item),
    );
    if (confirmed != true) return;
    await ref
        .read(eventRepositoryProvider)
        .removeBooking(item.event.id, dayIndex: item.participant.dayIndex);
    await _refresh();
  }

  Future<void> _shareBooking(
    _MyBookingItem item,
    List<_MyBookingItem> allItems,
  ) async {
    final bookings = allItems
        .where((row) => row.event.id == item.event.id)
        .map((row) => row.participant)
        .toList();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EventBookingSharePage(event: item.event, bookings: bookings),
      ),
    );
  }
}

class _MyEventsLoadingState extends StatelessWidget {
  const _MyEventsLoadingState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CosPageHeader(
          title: '我的活動',
          subtitle: '正在整理你的參戰票夾',
          leading: CosIconBubble(icon: Icons.event_available_outlined),
        ),
        const SizedBox(height: 8),
        CosGradientPanel(
          icon: Icons.confirmation_number_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CosSectionHeader(
                title: '同步參戰名片',
                subtitle: '整理即將出席的場次、角色名片與分享圖素材',
                icon: Icons.wallet_outlined,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var index = 0; index < 3; index += 1) ...[
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              (index == 0
                                      ? scheme.primary
                                      : index == 1
                                      ? scheme.secondary
                                      : scheme.tertiary)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(CosUi.radiusMd),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.34,
                            ),
                          ),
                        ),
                        child: const SizedBox(height: 64),
                      ),
                    ),
                    if (index < 2) const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < 2; index += 1) ...[
          _MyBookingSkeletonCard(compact: index == 1),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MyBookingSkeletonCard extends StatelessWidget {
  const _MyBookingSkeletonCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.12),
                  scheme.surfaceContainerLowest,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CosUi.radiusLg),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: scheme.primary.withValues(alpha: 0.18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MyEventsSkeletonLine(widthFactor: 0.72, height: 16),
                        const SizedBox(height: 9),
                        _MyEventsSkeletonLine(
                          widthFactor: compact ? 0.44 : 0.62,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: _MyEventsSkeletonLine(widthFactor: 0.88)),
                const SizedBox(width: 10),
                Expanded(child: _MyEventsSkeletonLine(widthFactor: 0.72)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyEventsSkeletonLine extends StatelessWidget {
  const _MyEventsSkeletonLine({required this.widthFactor, this.height = 10});

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

class _MyBookingItem {
  const _MyBookingItem({required this.event, required this.participant});

  final CosEvent event;
  final EventParticipant participant;

  int get dayIndex => participant.dayIndex;

  DateTime get date => event.startDate.add(Duration(days: dayIndex - 1));

  String get title => eventDayTitle(event, dayIndex);

  bool get isEnded {
    final today = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    return DateTime(today.year, today.month, today.day).isAfter(dateOnly);
  }
}

class _MyBookingCard extends StatelessWidget {
  const _MyBookingCard({
    required this.item,
    required this.onEdit,
    required this.onCancel,
    required this.onShare,
  });

  final _MyBookingItem item;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final participant = item.participant;
    final scheme = Theme.of(context).colorScheme;
    final roleColor = participantRoleColorForScheme(participant.role, scheme);
    final textColor = item.isEnded ? scheme.onSurfaceVariant : scheme.onSurface;
    return Opacity(
      opacity: item.isEnded ? 0.74 : 1,
      child: CosCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    roleColor.withValues(alpha: 0.18),
                    scheme.surfaceContainerLowest,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(CosUi.radiusLg),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CosIconBubble(
                      icon: Icons.confirmation_number_outlined,
                      color: roleColor,
                      size: 46,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              CosBadge(
                                label: participantRoleLabel(participant.role),
                                icon: Icons.badge_outlined,
                                highlighted: true,
                                color: roleColor,
                              ),
                              CosBadge(
                                label: item.isEnded ? '已結束' : '準備中',
                                icon: item.isEnded
                                    ? Icons.history
                                    : Icons.event_available_outlined,
                                color: item.isEnded
                                    ? scheme.outline
                                    : scheme.secondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'yyyy/MM/dd E',
                              'zh_TW',
                            ).format(item.date),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CosMetricTile(
                          icon: Icons.auto_awesome,
                          label: '角色',
                          value: participant.characterName.isEmpty
                              ? '未填寫'
                              : participant.characterName,
                          color: roleColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CosMetricTile(
                          icon: Icons.photo_library_outlined,
                          label: '分享素材',
                          value: participant.outfitImageUrl.isEmpty
                              ? '待補'
                              : '已準備',
                          color: scheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  if (participant.message.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    CosInfoTile(
                      icon: Icons.chat_bubble_outline,
                      label: '備註',
                      value: participant.message,
                      color: scheme.secondary,
                    ),
                  ],
                  if (participant.interactionTags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in participant.interactionTags)
                          CosBadge(
                            label: tag,
                            icon: Icons.waving_hand_outlined,
                            color: scheme.secondary,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('修改'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: '取消預訂',
                        onPressed: onCancel,
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onShare,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('產圖'),
                        ),
                      ),
                    ],
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

class _MyEventsEmptyState extends StatelessWidget {
  const _MyEventsEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Row(
        children: [
          CosIconBubble(
            icon: Icons.event_busy_outlined,
            color: scheme.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '目前沒有符合條件的預訂。加入活動後，這裡會變成你的參戰票夾。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelBookingDialog extends StatelessWidget {
  const _CancelBookingDialog({required this.item});

  final _MyBookingItem item;

  @override
  Widget build(BuildContext context) {
    return CosSafetyConfirmDialog(
      title: '取消預訂',
      message: '確定要取消 ${item.title} 的預訂嗎？取消後同好將看不到這張參戰名片。',
      actionLabel: '取消預訂',
      cancelLabel: '保留',
      icon: Icons.delete_outline,
      destructive: true,
    );
  }
}
