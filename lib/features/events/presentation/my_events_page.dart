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
              return const Center(child: CircularProgressIndicator());
            }
            final allItems = snapshot.data!..sort(_compareBookingItems);
            final visibleItems = allItems
                .where((item) => _showEnded || !item.isEnded)
                .toList();
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
                      FilterChip(
                        label: const Text('顯示已過期'),
                        selected: _showEnded,
                        onSelected: (value) =>
                            setState(() => _showEnded = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (visibleItems.isEmpty)
                    const CosCard(child: Text('目前沒有符合條件的預訂'))
                  else
                    for (final item in visibleItems) ...[
                      _MyBookingCard(
                        item: item,
                        onEdit: () => _editBooking(item),
                        onCancel: () => _cancelBooking(item),
                        onShare: () => _shareBooking(item, allItems),
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
      builder: (context) => AlertDialog(
        title: const Text('取消預訂'),
        content: Text('確定要取消 ${item.title} 的預訂嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消預訂'),
          ),
        ],
      ),
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
    final textColor = item.isEnded
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurface;
    return Opacity(
      opacity: item.isEnded ? 0.74 : 1,
      child: CosCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CosIconBubble(
                  icon: Icons.confirmation_number_outlined,
                  color: participantRoleColorForScheme(
                    participant.role,
                    Theme.of(context).colorScheme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('yyyy/MM/dd E', 'zh_TW').format(item.date),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                CosBadge(label: participantRoleLabel(participant.role)),
              ],
            ),
            if (participant.characterName.isNotEmpty) ...[
              const SizedBox(height: 10),
              CosBadge(
                label: participant.characterName,
                icon: Icons.face_retouching_natural_outlined,
              ),
            ],
            if (participant.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                participant.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改'),
                ),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('產圖'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
