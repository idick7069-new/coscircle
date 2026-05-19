import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/models/event.dart';
import '../../../core/models/participant.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/app_page.dart';

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
                eventId: eventId,
                participants: participants,
              ),
            ],
          );
        },
        error: (error, stack) => Center(child: Text('活動載入失敗：$error')),
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
    required this.eventId,
    required this.participants,
  });

  final String eventId;
  final AsyncValue<List<EventParticipant>> participants;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return participants.when(
      data: (items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '今天誰會去 ${items.length}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (items.any((item) => item.isFollowed))
                  const Chip(label: Text('已有關注者參加')),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('目前還沒有人發布出席宣告'),
                ),
              )
            else
              Column(
                children: [
                  for (final participant in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ParticipantCard(
                        participant: participant,
                        onTap: () =>
                            _showParticipantSheet(context, ref, participant),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
      error: (error, stack) => Text('參加者載入失敗：$error'),
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
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: participant.isFollowed
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.primaryContainer,
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
                          Text(_presenceStatusText(participant.presenceStatus)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (participant.availableTime.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('出沒時間：${participant.availableTime}'),
                ],
                if (participant.interactionTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in participant.interactionTags)
                        Chip(label: Text(tag)),
                    ],
                  ),
                ],
                if (participant.message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(participant.message),
                ],
                if (participant.bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('自我介紹：${participant.bio}'),
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
                          Text('當天穿著：${participant.outfitImageUrl}'),
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
                        onPressed: () {},
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
    return switch (participant.role) {
      'photographer' => '攝影',
      'coser' => [
        'Coser',
        if (participant.workName.isNotEmpty) participant.workName,
        if (participant.characterName.isNotEmpty) participant.characterName,
      ].join(' / '),
      'self' => '本體',
      _ => '參加者',
    };
  }

  String _presenceStatusText(String status) {
    return switch (status) {
      'moving' => '移動中',
      'resting' => '休息中',
      'quiet' => '暫不互動',
      'left' => '已離場',
      _ => '可來找我',
    };
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({required this.participant, required this.onTap});

  final EventParticipant participant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: pickedImageProvider(participant.avatarUrl),
                child: participant.avatarUrl.isEmpty
                    ? Text(participant.nickname.characters.firstOrNull ?? '?')
                    : null,
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
                            participant.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (participant.isFollowed)
                          const Icon(Icons.star, size: 18),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _roleText(participant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (participant.availableTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        participant.availableTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (participant.interactionTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in participant.interactionTags.take(4))
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(tag),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleText(EventParticipant participant) {
    return switch (participant.role) {
      'photographer' => '攝影',
      'coser' => [
        'Coser',
        if (participant.workName.isNotEmpty) participant.workName,
        if (participant.characterName.isNotEmpty) participant.characterName,
      ].join(' / '),
      'self' => '本體',
      _ => '參加者',
    };
  }
}
