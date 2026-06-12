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
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../shared/widgets/app_page.dart';
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
              if (value.imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(
                    image: pickedImageProvider(value.imageUrl)!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                value.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
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
              Text('活動說明', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(value.description.isEmpty ? '未提供活動說明' : value.description),
              const SizedBox(height: 24),
              _ParticipantsSection(
                event: value,
                eventId: eventId,
                participants: participants,
              ),
            ],
          );
        },
        error: (error, stack) =>
            Center(child: Text('活動載入失敗：${userFacingError(error)}')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
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
      ),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '參加者 ${items.length}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (items.any((item) => item.isFollowed))
                  const Chip(label: Text('已有關注者參加')),
              ],
            ),
            const SizedBox(height: 12),
            if (myBookings.isNotEmpty) ...[
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
              const SizedBox(height: 12),
            ],
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('目前還沒有人公開預訂'),
                ),
              )
            else
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
        );
      },
      error: (error, stack) => Text('參加者載入失敗：${userFacingError(error)}'),
      loading: () => const Center(child: CircularProgressIndicator()),
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

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({required this.participant, required this.onTap});

  final EventParticipant participant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: participantRoleColor(participant.role),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: pickedImageProvider(participant.avatarUrl),
              child: participant.avatarUrl.isEmpty
                  ? Text(participant.nickname.characters.firstOrNull ?? '?')
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 72,
            child: Text(
              participant.nickname,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
