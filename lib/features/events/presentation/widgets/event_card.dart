import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/event.dart';
import '../../../../core/models/participant.dart';
import '../../../../core/providers/event_providers.dart';
import '../../../../core/utils/event_day_display.dart';
import '../../../../core/utils/picked_image_provider.dart';
import '../../../../shared/widgets/cos_ui.dart';

class EventCard extends ConsumerWidget {
  const EventCard({
    super.key,
    required this.event,
    this.title,
    this.dateText,
    required this.onBookingPressed,
    required this.onDetailPressed,
    this.isJoinedOverride,
    this.statusOverride,
    this.dayIndex,
  });

  final CosEvent event;
  final String? title;
  final String? dateText;
  final VoidCallback? onBookingPressed;
  final VoidCallback onDetailPressed;
  final bool? isJoinedOverride;
  final EventStatus? statusOverride;
  final int? dayIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date =
        dateText ??
        (event.startDate == event.endDate
            ? DateFormat('yyyy/MM/dd E', 'zh_TW').format(event.startDate)
            : '${DateFormat('yyyy/MM/dd').format(event.startDate)} - ${DateFormat('MM/dd').format(event.endDate)}');
    final status = statusOverride ?? event.status(DateTime.now());
    final isEnded = status == EventStatus.ended;
    final isJoined = isJoinedOverride ?? event.isJoined;
    final participants = ref
        .watch(eventParticipantsProvider(event.id))
        .whenData(
          (items) => dayIndex == null
              ? items
              : items.where((item) => item.dayIndex == dayIndex).toList(),
        );
    final statusText = switch (status) {
      EventStatus.ended => '已結束',
      EventStatus.active => '正在進行',
      EventStatus.upcoming => '尚未到來',
    };
    final textColor = isEnded
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurface;
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: isEnded ? 0.72 : 1,
      child: CosCard(
        onTap: onDetailPressed,
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
                  constraints: const BoxConstraints(minHeight: 126),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compactActions = constraints.maxWidth < 250;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              CosBadge(label: event.category),
                              CosBadge(
                                label: statusText,
                                highlighted: status == EventStatus.active,
                                color: status == EventStatus.active
                                    ? scheme.secondary
                                    : scheme.tertiary,
                              ),
                              CosBadge(
                                label: event.sourceName,
                                icon: _sourceIcon(event.sourceType),
                                color: scheme.tertiary,
                              ),
                              if (dayIndex == null
                                  ? event.hasFriends
                                  : event.friendDayIndexes.contains(dayIndex))
                                CosBadge(
                                  label: '戳友會去',
                                  icon: Icons.people_outline,
                                  color: scheme.secondary,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title ?? eventDisplayName(event),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                ),
                          ),
                          const SizedBox(height: 5),
                          _IconLine(
                            icon: Icons.schedule,
                            iconColor: scheme.tertiary,
                            text: date,
                          ),
                          const SizedBox(height: 4),
                          _IconLine(
                            icon: Icons.place_outlined,
                            iconColor: scheme.secondary,
                            text: event.venue,
                          ),
                          const SizedBox(height: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ParticipantStrip(participants: participants),
                              const SizedBox(height: 8),
                              Wrap(
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
                                      isJoined
                                          ? Icons.edit_outlined
                                          : Icons.add_circle_outline,
                                    ),
                                    label: Text(isJoined ? '修改' : '加入'),
                                  ),
                                ],
                              ),
                            ],
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
    );
  }

  ButtonStyle _compactButtonStyle() {
    return OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  ButtonStyle _compactFilledButtonStyle() {
    return FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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

IconData _sourceIcon(int sourceType) {
  return switch (sourceType) {
    1 => Icons.public,
    2 => Icons.how_to_vote_outlined,
    3 => Icons.verified_user_outlined,
    4 => Icons.auto_awesome_outlined,
    5 => Icons.photo_camera_outlined,
    _ => Icons.link_outlined,
  };
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
      width: 96,
      height: 128,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(Icons.photo_camera_outlined, size: 34, color: scheme.primary),
    );

    final image = imageUrl.isEmpty
        ? placeholder
        : Image(
            image: pickedImageProvider(imageUrl)!,
            width: 96,
            height: 128,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );

    return SizedBox(
      width: 96,
      height: 128,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isEnded ? scheme.outline : scheme.tertiary,
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
                          : scheme.tertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
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
          return Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '尚無公開參與者',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            CosAvatarStack(
              avatars: [
                for (final item in items) pickedImageProvider(item.avatarUrl),
              ],
              names: [for (final item in items) item.nickname],
              maxVisible: 6,
              radius: 11,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${items.length} 位同好',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
      error: (error, stackTrace) =>
          Text('參與者載入失敗', style: Theme.of(context).textTheme.bodySmall),
      loading: () => SizedBox(
        height: 24,
        width: 24,
        child: CosLoadingPulse(
          color: Theme.of(context).colorScheme.secondary,
          size: 22,
        ),
      ),
    );
  }
}
