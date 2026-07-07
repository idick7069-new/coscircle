import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/models/booking.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_day_item.dart';
import '../../../core/models/participant.dart';
import '../../../core/models/work.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../works/presentation/work_selector.dart';
import 'my_events_page.dart';
import 'widgets/event_card.dart';

class EventListPage extends ConsumerStatefulWidget {
  const EventListPage({super.key, required this.onOpenCurrentEvent});

  final ValueChanged<EventDayItem> onOpenCurrentEvent;

  @override
  ConsumerState<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends ConsumerState<EventListPage> {
  static const _filterKey = 'event_list_filter';
  static const _joinedOnlyKey = 'event_list_joined_only';
  static const _hideEndedKey = 'event_list_hide_ended';
  static const _selectedDayKey = 'event_list_selected_day';
  static const _focusedDayKey = 'event_list_focused_day';
  static const _validFilters = {'全部', '我有加入', '關注者', '小圈圈'};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _joinedOnly = false;
  bool _hideEnded = true;
  String _filter = '全部';

  @override
  void initState() {
    super.initState();
    _restoreFilters();
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    return RefreshIndicator(
      onRefresh: _refreshEvents,
      child: events.when(
        data: (items) {
          final expanded = expandEventDays(items);
          final filtered = _applyFilters(expanded);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CosPageHeader(
                  title: '活動發現',
                  subtitle: '用日期、作品和同好快速找到下一場',
                  actions: [
                    IconButton.filledTonal(
                      tooltip: '我的活動',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MyEventsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.event_available_outlined),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: _DiscoveryStats(events: items, filtered: filtered),
              ),
              if (filtered.isNotEmpty)
                SliverToBoxAdapter(
                  child: _EventSpotlightCard(
                    item: filtered.first,
                    onOpenCurrentEvent: widget.onOpenCurrentEvent,
                    onBookingPressed: (event, dayIndex) =>
                        _showBookingSheet(context, event, dayIndex: dayIndex),
                    onDetailPressed: (event) =>
                        context.push('/events/${event.id}'),
                  ),
                ),
              SliverToBoxAdapter(child: _calendar(items)),
              SliverToBoxAdapter(child: _filterChips()),
              if (filtered.isEmpty)
                const SliverToBoxAdapter(child: _EmptyEventResult())
              else
                SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final event = item.event;
                    final status = item.status(DateTime.now());
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: EventCard(
                        event: event,
                        title: item.title,
                        dateText: DateFormat(
                          'yyyy/MM/dd E',
                          'zh_TW',
                        ).format(item.date),
                        onTap: status == EventStatus.active
                            ? () => widget.onOpenCurrentEvent(item)
                            : null,
                        onBookingPressed: status == EventStatus.ended
                            ? null
                            : () => _showBookingSheet(
                                context,
                                event,
                                dayIndex: item.dayIndex,
                              ),
                        onDetailPressed: () =>
                            context.push('/events/${event.id}'),
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
        error: (error, stack) => _EventListStateView(
          icon: Icons.wifi_off_outlined,
          title: '活動載入失敗',
          message: userFacingError(error),
          actionLabel: '重新整理',
          onAction: () => ref.invalidate(eventsProvider),
        ),
        loading: () => const _EventListLoadingView(),
      ),
    );
  }

  Widget _calendar(List<CosEvent> events) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: CosCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: CosSectionHeader(
                title: '活動月曆',
                subtitle: '有標記的日期代表可加入或已參加的場次',
                icon: Icons.calendar_month_outlined,
              ),
            ),
            const SizedBox(height: 8),
            TableCalendar<CosEvent>(
              firstDay: DateTime(2026, 1, 1),
              lastDay: DateTime(2026, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: (day) => events.where((event) {
                final date = DateTime(day.year, day.month, day.day);
                return !date.isBefore(event.startDate) &&
                    !date.isAfter(event.endDate);
              }).toList(),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  final hasJoined = events.any((event) => event.isJoined);
                  return Positioned(
                    bottom: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final event in events.take(3))
                          Container(
                            width: hasJoined && event.isJoined ? 7 : 5,
                            height: hasJoined && event.isJoined ? 7 : 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: event.isJoined
                                  ? scheme.primary
                                  : scheme.secondary,
                              shape: BoxShape.circle,
                              border: event.isJoined
                                  ? Border.all(
                                      color: scheme.onPrimary,
                                      width: 1,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {CalendarFormat.month: '月'},
              onDaySelected: (selectedDay, focusedDay) {
                _updateFilters(
                  selectedDay: selectedDay,
                  focusedDay: focusedDay,
                );
              },
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: Theme.of(context).textTheme.titleMedium!
                    .copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: scheme.tertiary,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: scheme.tertiary,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
                weekendStyle: TextStyle(
                  color: scheme.secondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: TextStyle(color: scheme.onSurface),
                weekendTextStyle: TextStyle(color: scheme.secondary),
                markerDecoration: BoxDecoration(
                  color: scheme.secondary,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
                todayDecoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.24),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.tertiary),
                ),
                todayTextStyle: TextStyle(
                  color: scheme.tertiary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    final filters = ['全部', '我有加入', '關注者', '小圈圈'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: CosCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            CosSectionHeader(
              title: '快速篩選',
              subtitle: _selectedDay == null
                  ? '依參與關係和狀態縮小場次'
                  : '已鎖定 ${DateFormat('MM/dd E', 'zh_TW').format(_selectedDay!)}',
              icon: Icons.tune_outlined,
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in filters) ...[
                    CosChoicePill(
                      label: filter,
                      selected: _filter == filter,
                      icon: Icons.filter_alt_outlined,
                      onTap: () => _updateFilters(filter: filter),
                    ),
                    const SizedBox(width: 8),
                  ],
                  CosChoicePill(
                    label: '隱藏已結束',
                    selected: _hideEnded,
                    icon: Icons.event_busy_outlined,
                    color: Theme.of(context).colorScheme.secondary,
                    onTap: () => _updateFilters(hideEnded: !_hideEnded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<EventDayItem> _applyFilters(List<EventDayItem> items) {
    return items.where((item) {
      final event = item.event;
      final selected = _selectedDay;
      final matchesDate =
          selected == null ||
          (!DateTime(
                selected.year,
                selected.month,
                selected.day,
              ).isBefore(event.startDate) &&
              !DateTime(
                selected.year,
                selected.month,
                selected.day,
              ).isAfter(event.endDate));
      final matchesJoined =
          (!_joinedOnly && _filter != '我有加入') || event.isJoined;
      final matchesType = switch (_filter) {
        '關注者' => event.hasFollowedParticipants,
        '小圈圈' => event.hasCircleMembers,
        _ => true,
      };
      final matchesEnded =
          !_hideEnded || item.status(DateTime.now()) != EventStatus.ended;
      return matchesDate && matchesJoined && matchesType && matchesEnded;
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _restoreFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final filter = prefs.getString(_filterKey);
    final selectedDay = _parseSavedDate(prefs.getString(_selectedDayKey));
    final focusedDay = _parseSavedDate(prefs.getString(_focusedDayKey));
    setState(() {
      if (filter != null && _validFilters.contains(filter)) {
        _filter = filter;
      }
      _joinedOnly = prefs.getBool(_joinedOnlyKey) ?? false;
      _hideEnded = prefs.getBool(_hideEndedKey) ?? true;
      _selectedDay = selectedDay;
      _focusedDay = focusedDay ?? selectedDay ?? DateTime.now();
    });
  }

  void _updateFilters({
    String? filter,
    bool? joinedOnly,
    bool? hideEnded,
    DateTime? selectedDay,
    DateTime? focusedDay,
  }) {
    setState(() {
      if (filter != null) _filter = filter;
      if (joinedOnly != null) _joinedOnly = joinedOnly;
      if (hideEnded != null) _hideEnded = hideEnded;
      if (selectedDay != null) _selectedDay = selectedDay;
      if (focusedDay != null) _focusedDay = focusedDay;
    });
    _saveFilters();
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterKey, _filter);
    await prefs.setBool(_joinedOnlyKey, _joinedOnly);
    await prefs.setBool(_hideEndedKey, _hideEnded);
    await prefs.setString(_focusedDayKey, _dateOnly(_focusedDay));
    final selectedDay = _selectedDay;
    if (selectedDay == null) {
      await prefs.remove(_selectedDayKey);
    } else {
      await prefs.setString(_selectedDayKey, _dateOnly(selectedDay));
    }
  }

  DateTime? _parseSavedDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _showBookingSheet(
    BuildContext context,
    CosEvent event, {
    int dayIndex = 1,
  }) async {
    if (event.status(DateTime.now()) == EventStatus.ended) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          BookingSheet(event: event, initialDayIndex: dayIndex),
    );
  }

  Future<void> _refreshEvents() async {
    ref.invalidate(eventParticipantsProvider);
    await Future.wait([ref.refresh(eventsProvider.future)]);
  }
}

class _EventListLoadingView extends StatelessWidget {
  const _EventListLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: const [
        _EventListStateView(
          icon: Icons.radar_outlined,
          title: '正在掃描活動訊號',
          message: '整理近期場次、同好參與和小圈圈動態。',
        ),
        SizedBox(height: 14),
        _EventListSkeletonCard(),
        SizedBox(height: 10),
        _EventListSkeletonCard(compact: true),
      ],
    );
  }
}

class _EventListStateView extends StatelessWidget {
  const _EventListStateView({
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
    return CosReveal(
      child: CosGradientPanel(
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
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
    );
  }
}

class _EventListSkeletonCard extends StatelessWidget {
  const _EventListSkeletonCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
            ),
            child: SizedBox(width: 68, height: compact ? 58 : 78),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonLine(widthFactor: 0.74, height: 16),
                const SizedBox(height: 9),
                _SkeletonLine(widthFactor: compact ? 0.45 : 0.92),
                const SizedBox(height: 9),
                _SkeletonLine(widthFactor: compact ? 0.36 : 0.62),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, this.height = 10});

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

class _DiscoveryStats extends StatelessWidget {
  const _DiscoveryStats({required this.events, required this.filtered});

  final List<CosEvent> events;
  final List<EventDayItem> filtered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final joined = events.where((event) => event.isJoined).length;
    final social = events
        .where(
          (event) => event.hasFollowedParticipants || event.hasCircleMembers,
        )
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: CosMetricTile(
              icon: Icons.search_outlined,
              label: '篩選結果',
              value: '${filtered.length} 場',
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CosMetricTile(
              icon: Icons.check_circle_outline,
              label: '已加入',
              value: '$joined',
              color: scheme.secondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CosMetricTile(
              icon: Icons.diversity_3_outlined,
              label: '同好訊號',
              value: '$social',
              color: scheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEventResult extends StatelessWidget {
  const _EmptyEventResult();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: CosCard(
        child: Row(
          children: [
            CosIconBubble(
              icon: Icons.event_busy_outlined,
              color: scheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '目前沒有符合條件的場次，可以放寬篩選或改看其他日期。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventSpotlightCard extends StatelessWidget {
  const _EventSpotlightCard({
    required this.item,
    required this.onOpenCurrentEvent,
    required this.onBookingPressed,
    required this.onDetailPressed,
  });

  final EventDayItem item;
  final ValueChanged<EventDayItem> onOpenCurrentEvent;
  final void Function(CosEvent event, int dayIndex) onBookingPressed;
  final ValueChanged<CosEvent> onDetailPressed;

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final status = item.status(DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    final imageProvider = pickedImageProvider(event.imageUrl);
    final statusText = switch (status) {
      EventStatus.ended => '已結束',
      EventStatus.active => '正在進行',
      EventStatus.upcoming => '即將開始',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: CosCard(
        padding: EdgeInsets.zero,
        onTap: status == EventStatus.active
            ? () => onOpenCurrentEvent(item)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CosUi.radiusLg),
              ),
              child: AspectRatio(
                aspectRatio: 1.95,
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
                          Icons.photo_camera_outlined,
                          size: 58,
                          color: scheme.primary,
                        ),
                      )
                    else
                      Image(image: imageProvider, fit: BoxFit.cover),
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
                            label: statusText,
                            highlighted: status == EventStatus.active,
                            color: status == EventStatus.active
                                ? scheme.secondary
                                : scheme.tertiary,
                          ),
                          CosBadge(
                            label: event.category,
                            color: scheme.primary,
                          ),
                          if (event.isJoined)
                            CosBadge(
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
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SpotlightLine(
                          icon: Icons.calendar_month_outlined,
                          text: DateFormat(
                            'MM/dd E',
                            'zh_TW',
                          ).format(item.date),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SpotlightLine(
                          icon: Icons.place_outlined,
                          text: event.venue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '找到同作品、同圈圈的人，現場認親更快。',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => onDetailPressed(event),
                        child: const Text('詳細'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: status == EventStatus.ended
                            ? null
                            : () => onBookingPressed(event, item.dayIndex),
                        icon: Icon(
                          event.isJoined
                              ? Icons.edit_outlined
                              : Icons.add_circle_outline,
                        ),
                        label: Text(event.isJoined ? '修改' : '加入'),
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

class _SpotlightLine extends StatelessWidget {
  const _SpotlightLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CosIconBubble(icon: icon, size: 34, color: scheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
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

class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({
    super.key,
    required this.event,
    this.initialDayIndex = 1,
    this.initialParticipant,
  });

  final CosEvent event;
  final int initialDayIndex;
  final EventParticipant? initialParticipant;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  static const _interactionOptions = ['認親', '拍照', '交換無料', '聊天', '一起逛', '找同作品'];
  static const _statusOptions = [
    ('open', '可來找我'),
    ('moving', '移動中'),
    ('resting', '休息中'),
    ('quiet', '暫不互動'),
    ('left', '已離場'),
  ];

  ParticipantRole _role = ParticipantRole.coser;
  final _characterController = TextEditingController();
  final _availableTimeController = TextEditingController();
  final _messageController = TextEditingController();
  final Set<String> _interactionTags = {};
  String _presenceStatus = 'open';
  String? _outfitImagePath;
  XFile? _pickedOutfitImage;
  WorkTag? _selectedWork;
  int _dayIndex = 1;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _dayIndex = widget.initialDayIndex;
    final participant = widget.initialParticipant;
    if (participant == null) return;
    _role = _roleFromString(participant.role);
    _dayIndex = participant.dayIndex;
    _characterController.text = participant.characterName;
    _availableTimeController.text = participant.availableTime;
    _messageController.text = participant.message;
    _interactionTags.addAll(participant.interactionTags);
    _presenceStatus = participant.presenceStatus;
    _outfitImagePath = participant.outfitImageUrl.isEmpty
        ? null
        : participant.outfitImageUrl;
    if (participant.workId.isNotEmpty || participant.workName.isNotEmpty) {
      _selectedWork = WorkTag(
        id: participant.workId,
        name: participant.workName,
      );
    }
  }

  @override
  void dispose() {
    _characterController.dispose();
    _availableTimeController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final scheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final roleName = participantRoleLabel(_role.name);
    final roleColor = participantRoleColorForScheme(_role.name, scheme);

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.86),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              CosReveal(
                child: CosGradientPanel(
                  icon: Icons.badge_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CosSectionHeader(
                        title: widget.initialParticipant != null
                            ? '修改參戰名片'
                            : '建立參戰名片',
                        subtitle: '讓同好知道你哪天會到、扮什麼、怎麼找你互動',
                        icon: Icons.theater_comedy_outlined,
                        trailing: CosBadge(
                          label: roleName,
                          icon: Icons.badge_outlined,
                          highlighted: true,
                          color: roleColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: CosMetricTile(
                              icon: Icons.calendar_month_outlined,
                              label: '參加日',
                              value: 'D$_dayIndex',
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CosMetricTile(
                              icon: Icons.forum_outlined,
                              label: '互動方式',
                              value: _interactionTags.isEmpty
                                  ? '待選擇'
                                  : '${_interactionTags.length} 種',
                              color: scheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CosMetricTile(
                              icon: Icons.sensors_outlined,
                              label: '現場狀態',
                              value: _presenceStatusLabel(_presenceStatus),
                              color: scheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _BookingSection(
                title: '日期與身份',
                subtitle: '先決定這張名片代表哪一天、你在現場的角色',
                icon: Icons.event_available_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '參加日',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var index = 1;
                          index <= _eventDayCount(event);
                          index += 1
                        )
                          CosChoicePill(
                            label: 'D$index',
                            selected: _dayIndex == index,
                            icon: Icons.calendar_today_outlined,
                            onTap: () => setState(() => _dayIndex = index),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _RoleChoiceGrid(
                      selectedRole: _role,
                      onChanged: (role) => setState(() => _role = role),
                    ),
                  ],
                ),
              ),
              if (_role == ParticipantRole.coser) ...[
                const SizedBox(height: 12),
                _BookingSection(
                  title: '作品與角色',
                  subtitle: '這會成為同好認親時最先看到的資訊',
                  icon: Icons.auto_awesome,
                  child: Column(
                    children: [
                      WorkSingleSelector(
                        label: '作品',
                        selected: _selectedWork,
                        onChanged: (work) =>
                            setState(() => _selectedWork = work),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _characterController,
                        decoration: const InputDecoration(labelText: '角色名'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _BookingSection(
                title: '現場互動',
                subtitle: '把界線和歡迎方式講清楚，認親會更順',
                icon: Icons.forum_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _availableTimeController,
                      decoration: const InputDecoration(
                        labelText: '預計出沒時間',
                        hintText: '例如 13:00 - 16:00、午後、整天',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '歡迎互動方式',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _interactionOptions)
                          CosChoicePill(
                            label: option,
                            selected: _interactionTags.contains(option),
                            icon: Icons.add_circle_outline,
                            color: Theme.of(context).colorScheme.secondary,
                            onTap: () {
                              setState(() {
                                if (_interactionTags.contains(option)) {
                                  _interactionTags.remove(option);
                                } else {
                                  _interactionTags.add(option);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PresenceStatusSelector(
                      value: _presenceStatus,
                      options: _statusOptions,
                      onChanged: (value) =>
                          setState(() => _presenceStatus = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _BookingSection(
                title: '照片與備註',
                subtitle: '放一點辨識線索，現場比較容易找到彼此',
                icon: Icons.photo_library_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OutfitImagePicker(
                      imagePath: _outfitImagePath,
                      onPick: _pickOutfitImage,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        labelText: '備註',
                        hintText: '例如 看到我可以打招呼、社恐請先私訊',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _BookingSubmitBar(
                editing: widget.initialParticipant != null,
                submitting: _submitting,
                onRemove: widget.initialParticipant == null
                    ? null
                    : () => _removeAttendance(context, event),
                onSave: () => _saveAttendance(context, event),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickOutfitImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    setState(() {
      _outfitImagePath = image.path;
      _pickedOutfitImage = image;
    });
  }

  Future<void> _saveAttendance(BuildContext context, CosEvent event) async {
    setState(() => _submitting = true);
    try {
      var outfitImageUrl = _outfitImagePath;
      final pickedOutfitImage = _pickedOutfitImage;
      if (pickedOutfitImage != null) {
        final uploadedUrl = await ref
            .read(profileRepositoryProvider)
            .uploadImage(
              bytes: await pickedOutfitImage.readAsBytes(),
              mimeType: _mimeTypeForPath(pickedOutfitImage.path),
            );
        if (uploadedUrl.isNotEmpty) outfitImageUrl = uploadedUrl;
      }

      await ref
          .read(eventRepositoryProvider)
          .upsertBooking(
            EventBooking(
              eventId: event.id,
              role: _role,
              dayIndex: _dayIndex,
              workId: _role == ParticipantRole.coser ? _selectedWork?.id : null,
              characterName: _characterController.text,
              outfitImagePath: outfitImageUrl,
              interactionTags: _interactionTags.toList(),
              availableTime: _availableTimeController.text.trim(),
              presenceStatus: _presenceStatus,
              message: _messageController.text,
            ),
          );
      await _refreshAfterAttendanceChanged(event.id);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('儲存出席失敗：$error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  int _eventDayCount(CosEvent event) {
    return event.endDate.difference(event.startDate).inDays + 1;
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _removeAttendance(BuildContext context, CosEvent event) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(eventRepositoryProvider)
          .removeBooking(event.id, dayIndex: _dayIndex);
      await _refreshAfterAttendanceChanged(event.id);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取消出席失敗：$error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  ParticipantRole _roleFromString(String value) {
    return ParticipantRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => ParticipantRole.coser,
    );
  }

  Future<void> _refreshAfterAttendanceChanged(String eventId) async {
    ref.invalidate(eventParticipantsProvider(eventId));
    await Future.wait([
      ref.refresh(eventsProvider.future),
      ref.refresh(eventParticipantsProvider(eventId).future),
    ]);
  }

  String _presenceStatusLabel(String value) {
    return _statusOptions
            .where((option) => option.$1 == value)
            .map((option) => option.$2)
            .firstOrNull ??
        value;
  }
}

class _BookingSection extends StatelessWidget {
  const _BookingSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CosReveal(
      offset: const Offset(0, 10),
      child: CosCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosSectionHeader(title: title, subtitle: subtitle, icon: icon),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RoleChoiceGrid extends StatelessWidget {
  const _RoleChoiceGrid({required this.selectedRole, required this.onChanged});

  final ParticipantRole selectedRole;
  final ValueChanged<ParticipantRole> onChanged;

  static const _roles = [
    (ParticipantRole.photographer, Icons.camera_alt_outlined, '攝影', '捕捉現場'),
    (
      ParticipantRole.coser,
      Icons.face_retouching_natural_outlined,
      'Coser',
      '角色亮相',
    ),
    (ParticipantRole.manager, Icons.support_agent_outlined, '馬內', '協助同行'),
    (ParticipantRole.self, Icons.person_pin_circle_outlined, '路人', '自由逛場'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in _roles)
              SizedBox(
                width: narrow
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 8) / 2,
                child: _RoleChoiceCard(
                  role: role.$1,
                  icon: role.$2,
                  title: role.$3,
                  subtitle: role.$4,
                  selected: selectedRole == role.$1,
                  onTap: () => onChanged(role.$1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.role,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final ParticipantRole role;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = participantRoleColorForScheme(role.name, scheme);
    return InkWell(
      borderRadius: BorderRadius.circular(CosUi.radiusMd),
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            CosIconBubble(icon: icon, color: accent, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              scale: selected ? 1 : 0.86,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? accent : scheme.outline,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceStatusSelector extends StatelessWidget {
  const _PresenceStatusSelector({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '現場狀態',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              CosChoicePill(
                label: option.$2,
                selected: value == option.$1,
                icon: _presenceStatusIcon(option.$1),
                color: _presenceStatusColor(scheme, option.$1),
                onTap: () => onChanged(option.$1),
              ),
          ],
        ),
      ],
    );
  }

  IconData _presenceStatusIcon(String value) {
    return switch (value) {
      'open' => Icons.waving_hand_outlined,
      'moving' => Icons.directions_walk_outlined,
      'resting' => Icons.local_cafe_outlined,
      'quiet' => Icons.do_not_disturb_on_outlined,
      'left' => Icons.logout_outlined,
      _ => Icons.info_outline,
    };
  }

  Color _presenceStatusColor(ColorScheme scheme, String value) {
    return switch (value) {
      'open' => scheme.secondary,
      'moving' => scheme.primary,
      'resting' => scheme.tertiary,
      'quiet' => scheme.error,
      'left' => scheme.onSurfaceVariant,
      _ => scheme.primary,
    };
  }
}

class _BookingSubmitBar extends StatelessWidget {
  const _BookingSubmitBar({
    required this.editing,
    required this.submitting,
    required this.onSave,
    this.onRemove,
  });

  final bool editing;
  final bool submitting;
  final VoidCallback onSave;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (onRemove != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : onRemove,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('取消出席'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: submitting ? null : onSave,
                icon: submitting
                    ? CosLoadingPulse(color: scheme.onPrimary, size: 20)
                    : Icon(
                        editing
                            ? Icons.save_outlined
                            : Icons.how_to_reg_outlined,
                      ),
                label: Text(
                  submitting
                      ? '同步中'
                      : editing
                      ? '儲存出席'
                      : '我會去',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitImagePicker extends StatelessWidget {
  const _OutfitImagePicker({required this.imagePath, required this.onPick});

  final String? imagePath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CosUi.radiusLg),
      onTap: onPick,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(CosUi.radiusLg),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CosUi.radiusMd),
                  child: imagePath == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.secondary.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: scheme.secondary,
                          ),
                        )
                      : Image(
                          image: pickedImageProvider(imagePath!)!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                ),
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      imagePath == null ? '當天長這樣' : '已選擇照片',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      imagePath == null ? '上傳一張方便同好認出你的照片' : imagePath!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
