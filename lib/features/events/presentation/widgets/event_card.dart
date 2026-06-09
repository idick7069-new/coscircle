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
    this.title,
    this.dateText,
    required this.onTap,
    required this.onBookingPressed,
    required this.onDetailPressed,
  });

  final CosEvent event;
  final String? title;
  final String? dateText;
  final VoidCallback? onTap;
  final VoidCallback? onBookingPressed;
  final VoidCallback onDetailPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date =
        dateText ??
        (event.startDate == event.endDate
            ? DateFormat('yyyy/MM/dd E', 'zh_TW').format(event.startDate)
            : '${DateFormat('yyyy/MM/dd').format(event.startDate)} - ${DateFormat('MM/dd').format(event.endDate)}');
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
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: isEnded
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.7)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isEnded ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EventImage(
                  imageUrl: event.imageUrl,
                  isEnded: isEnded,
                  statusText: statusText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 116),
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
                                _EventTag(
                                  label: statusText,
                                  highlighted: status == EventStatus.active,
                                ),
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
                              title ?? event.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            _IconLine(
                              icon: Icons.schedule,
                              iconColor: scheme.tertiary,
                              text: date,
                            ),
                            const SizedBox(height: 3),
                            _IconLine(
                              icon: Icons.place_outlined,
                              iconColor: scheme.secondary,
                              text: event.venue,
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
                                  OutlinedButton.icon(
                                    onPressed: onDetailPressed,
                                    style: _compactButtonStyle(),
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(compactActions ? '詳情' : '詳細'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: isEnded
                                        ? null
                                        : onBookingPressed,
                                    style: _compactFilledButtonStyle(),
                                    icon: Icon(
                                      event.isJoined
                                          ? Icons.edit_outlined
                                          : Icons.add_circle_outline,
                                    ),
                                    label: Text(event.isJoined ? '修改' : '加入'),
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

class _IconLine extends StatelessWidget {
  const _IconLine({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _EventTag extends StatelessWidget {
  const _EventTag({required this.label, this.icon, this.highlighted = false});

  final String label;
  final IconData? icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.secondary.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted ? scheme.secondary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: highlighted ? scheme.secondary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlighted ? scheme.secondary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventImage extends StatelessWidget {
  const _EventImage({
    required this.imageUrl,
    required this.isEnded,
    required this.statusText,
  });

  final String imageUrl;
  final bool isEnded;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 92,
      height: 112,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(Icons.event, size: 34, color: scheme.onPrimaryContainer),
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

    return SizedBox(
      width: 92,
      height: 112,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            isEnded
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.grey,
                      BlendMode.saturation,
                    ),
                    child: image,
                  )
                : image,
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isEnded ? scheme.outline : scheme.secondary,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  child: Text(
                    statusText,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isEnded
                          ? scheme.onSurfaceVariant
                          : scheme.secondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
                        color: participantRoleColorForScheme(
                          entry.$2.role,
                          Theme.of(context).colorScheme,
                        ),
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
