import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/participant.dart';
import '../../../core/models/work.dart';
import '../../../core/providers/event_providers.dart';

int matchingCoserCount(
  List<EventParticipant> participants, {
  required int dayIndex,
  required String workId,
}) {
  if (workId.isEmpty) return 0;
  return participants
      .where(
        (person) =>
            !person.isMe &&
            person.role == 'coser' &&
            person.dayIndex == dayIndex &&
            person.workId == workId,
      )
      .map((person) => person.userId)
      .toSet()
      .length;
}

class SameWorkCoserNotice extends ConsumerWidget {
  const SameWorkCoserNotice({
    super.key,
    required this.eventId,
    required this.dayIndex,
    required this.work,
  });
  final String eventId;
  final int dayIndex;
  final WorkTag work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref.watch(eventParticipantsProvider(eventId));
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          border: Border.all(color: scheme.secondary),
        ),
        child: participants.when(
          skipLoadingOnReload: true,
          data: (people) {
            final count = matchingCoserCount(
              people,
              dayIndex: dayIndex,
              workId: work.id,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 0
                      ? '目前還沒有其他 Coser 預訂這部作品'
                      : '已有 $count 位 Coser 也要出「${work.name}」',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '同場同日・依可見預訂計算，不含自己',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            );
          },
          loading: () => Text(
            '正在確認同作品 Coser…',
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          error: (_, _) => Row(
            children: [
              Expanded(
                child: Text(
                  '同作品人數暫時無法取得',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
              IconButton(
                tooltip: '重新確認同作品人數',
                onPressed: () =>
                    ref.invalidate(eventParticipantsProvider(eventId)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
