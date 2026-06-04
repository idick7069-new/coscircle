import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/event.dart';
import '../../../../core/models/participant.dart';
import '../../../../core/providers/event_providers.dart';
import '../../../../core/utils/picked_image_provider.dart';
import '../../../../core/utils/participant_role_style.dart';

class EventCard extends ConsumerWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    required this.onBookingPressed,
    required this.onDetailPressed,
  });

  final CosEvent event;
  final VoidCallback? onTap;
  final VoidCallback? onBookingPressed;
  final VoidCallback onDetailPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = event.startDate == event.endDate
        ? DateFormat('yyyy/MM/dd E', 'zh_TW').format(event.startDate)
        : '${DateFormat('yyyy/MM/dd').format(event.startDate)} - ${DateFormat('MM/dd').format(event.endDate)}';
    final status = event.status(DateTime.now());
    final isEnded = status == EventStatus.ended;
    final participants = ref.watch(eventParticipantsProvider(event.id));
    final statusText = switch (status) {
      EventStatus.ended => '已結束',
      EventStatus.active => '正在進行',
      EventStatus.upcoming => '尚未到來',
    };
    final textColor = isEnded
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurface;

    return Card(
      color: isEnded
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isEnded ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EventImage(imageUrl: event.imageUrl, isEnded: isEnded),
                const SizedBox(width: 10),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 112),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compactActions = constraints.maxWidth < 250;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                _EventTag(label: event.category),
                                _EventTag(label: statusText),
                                _EventTag(
                                  label: event.sourceName,
                                  icon: event.sourceType == 1
                                      ? Icons.public
                                      : Icons.how_to_vote_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              event.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.venue,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            _ParticipantStrip(participants: participants),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton(
                                    onPressed: onDetailPressed,
                                    style: _compactButtonStyle(),
                                    child: Text(compactActions ? '詳情' : '詳細'),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: isEnded
                                        ? null
                                        : onBookingPressed,
                                    style: _compactFilledButtonStyle(),
                                    child: Text(event.isJoined ? '修改' : '加入'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _compactButtonStyle() {
    return OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  ButtonStyle _compactFilledButtonStyle() {
    return FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _EventTag extends StatelessWidget {
  const _EventTag({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventImage extends StatelessWidget {
  const _EventImage({required this.imageUrl, required this.isEnded});

  final String imageUrl;
  final bool isEnded;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 92,
      height: 112,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Icon(Icons.event, size: 34),
    );

    final image = imageUrl.isEmpty
        ? placeholder
        : Image(
            image: pickedImageProvider(imageUrl)!,
            width: 92,
            height: 112,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: isEnded
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.grey,
                BlendMode.saturation,
              ),
              child: image,
            )
          : image,
    );
  }
}

class _ParticipantStrip extends StatelessWidget {
  const _ParticipantStrip({required this.participants});

  final AsyncValue<List<EventParticipant>> participants;

  @override
  Widget build(BuildContext context) {
    return participants.when(
      data: (items) {
        if (items.isEmpty) {
          return Text(
            '尚無公開參與者',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return SizedBox(
          height: 24,
          child: Stack(
            children: [
              for (final entry in items.take(10).indexed)
                Positioned(
                  left: entry.$1 * 17,
                  child: Tooltip(
                    message: entry.$2.nickname,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: participantRoleColor(entry.$2.role),
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage: pickedImageProvider(
                          entry.$2.avatarUrl,
                        ),
                        child: entry.$2.avatarUrl.isEmpty
                            ? Text(
                                entry.$2.nickname.characters.firstOrNull ?? '?',
                                style: Theme.of(context).textTheme.labelSmall,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      error: (error, stackTrace) =>
          Text('參與者載入失敗', style: Theme.of(context).textTheme.bodySmall),
      loading: () => const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
