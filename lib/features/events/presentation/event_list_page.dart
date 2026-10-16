import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/models/event.dart';
import '../../../core/models/event_day_item.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'my_events_page.dart';
import 'widgets/event_card.dart';
import 'event_booking_sheet.dart';
export 'event_booking_sheet.dart' show BookingSheet;

class EventListPage extends ConsumerStatefulWidget {
  const EventListPage({super.key, required this.onOpenCurrentEvent});

  final ValueChanged<EventDayItem> onOpenCurrentEvent;

  @override
  ConsumerState<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends ConsumerState<EventListPage> {
  static const _filterKey = 'event_list_filter';
  static const _joinedOnlyKey = 'event_list_joined_only';
  static const _hideEndedKey = 'event_list_hide_ended_v2';
  static const _selectedDayKey = 'event_list_selected_day';
  static const _focusedDayKey = 'event_list_focused_day';
  static const _validFilters = {'全部', '我有加入', '關注者', '小圈圈', '戳友'};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _joinedOnly = false;
  bool _hideEnded = false;
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
              SliverToBoxAdapter(child: _calendar(expanded)),
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
                        isJoinedOverride: item.isJoined,
                        statusOverride: status,
                        dayIndex: item.dayIndex,
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

  Widget _calendar(List<EventDayItem> items) {
    final scheme = Theme.of(context).colorScheme;
    final firstDay = _calendarFirstDay(items);
    final lastDay = _calendarLastDay(items);
    final focusedDay = _calendarFocusedDay(firstDay, lastDay);
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
            TableCalendar<EventDayItem>(
              firstDay: firstDay,
              lastDay: lastDay,
              focusedDay: focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: (day) => items.where((item) {
                final date = DateTime(day.year, day.month, day.day);
                return DateTime(
                      item.date.year,
                      item.date.month,
                      item.date.day,
                    ) ==
                    date;
              }).toList(),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, dayItems) {
                  if (dayItems.isEmpty) return null;
                  final hasJoined = dayItems.any((item) => item.isJoined);
                  return Positioned(
                    bottom: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in dayItems.take(3))
                          Container(
                            width: hasJoined && item.isJoined ? 7 : 5,
                            height: hasJoined && item.isJoined ? 7 : 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: item.isJoined
                                  ? scheme.primary
                                  : scheme.secondary,
                              shape: BoxShape.circle,
                              border: item.isJoined
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
              availableGestures: AvailableGestures.horizontalSwipe,
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
    final filters = ['全部', '我有加入', '關注者', '小圈圈', '戳友'];
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
                  if (_selectedDay != null) ...[
                    const SizedBox(width: 8),
                    CosChoicePill(
                      label: '清除日期',
                      selected: false,
                      icon: Icons.event_repeat_outlined,
                      onTap: _clearSelectedDay,
                    ),
                  ],
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
      final selected = _selectedDay;
      final matchesDate =
          selected == null ||
          DateTime(item.date.year, item.date.month, item.date.day) ==
              DateTime(selected.year, selected.month, selected.day);
      final matchesJoined =
          (!_joinedOnly && _filter != '我有加入') || item.isJoined;
      final matchesType = switch (_filter) {
        '關注者' => item.hasFollowedParticipants,
        '小圈圈' => item.hasCircleMembers,
        '戳友' => item.hasFriends,
        _ => true,
      };
      final matchesEnded =
          !_hideEnded || item.status(DateTime.now()) != EventStatus.ended;
      return matchesDate && matchesJoined && matchesType && matchesEnded;
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  DateTime _calendarFirstDay(List<EventDayItem> items) {
    final now = DateTime.now();
    final dates = items.map((item) => item.date).toList();
    final earliest = dates.isEmpty
        ? DateTime(now.year, 1, 1)
        : dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final firstYear = earliest.year < now.year ? earliest.year : now.year;
    return DateTime(firstYear, 1, 1);
  }

  DateTime _calendarLastDay(List<EventDayItem> items) {
    final now = DateTime.now();
    final dates = items.map((item) => item.date).toList();
    final latest = dates.isEmpty
        ? DateTime(now.year, 12, 31)
        : dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final lastYear = latest.year > now.year ? latest.year : now.year;
    return DateTime(lastYear, 12, 31);
  }

  DateTime _calendarFocusedDay(DateTime firstDay, DateTime lastDay) {
    if (_focusedDay.isBefore(firstDay)) return firstDay;
    if (_focusedDay.isAfter(lastDay)) return lastDay;
    return _focusedDay;
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
      _hideEnded = prefs.getBool(_hideEndedKey) ?? false;
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
    bool clearSelectedDay = false,
  }) {
    setState(() {
      if (filter != null) _filter = filter;
      if (joinedOnly != null) _joinedOnly = joinedOnly;
      if (hideEnded != null) _hideEnded = hideEnded;
      if (clearSelectedDay) _selectedDay = null;
      if (selectedDay != null) _selectedDay = selectedDay;
      if (focusedDay != null) _focusedDay = focusedDay;
    });
    _saveFilters();
  }

  void _clearSelectedDay() {
    _updateFilters(clearSelectedDay: true);
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
    await showEventBookingSheet(context, ref, event, dayIndex: dayIndex);
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
      key: const ValueKey('event-discovery-summary'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CosBadge(
            label: '${filtered.length} 場活動',
            icon: Icons.event_outlined,
            color: scheme.primary,
          ),
          CosBadge(
            label: '已加入 $joined',
            icon: Icons.check_circle_outline,
            color: scheme.secondary,
          ),
          CosBadge(
            label: '同好訊號 $social',
            icon: Icons.diversity_3_outlined,
            color: scheme.tertiary,
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
      child: CosReveal(
        delay: const Duration(milliseconds: 120),
        child: CosCard(
          padding: EdgeInsets.zero,
          onTap: () => onDetailPressed(event),
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
                            if (item.isJoined)
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 360;
                        final actions = [
                          OutlinedButton(
                            onPressed: () => onDetailPressed(event),
                            child: const Text('詳細'),
                          ),
                          FilledButton.icon(
                            onPressed: status == EventStatus.ended
                                ? null
                                : () => onBookingPressed(event, item.dayIndex),
                            icon: Icon(
                              item.isJoined
                                  ? Icons.edit_outlined
                                  : Icons.add_circle_outline,
                            ),
                            label: Text(item.isJoined ? '修改' : '加入'),
                          ),
                        ];
                        final message = Text(
                          '找到同作品、同圈圈的人，現場認親更快。',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              message,
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                children: actions,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: message),
                            const SizedBox(width: 10),
                            ...actions.expand(
                              (action) => [
                                action,
                                if (action != actions.last)
                                  const SizedBox(width: 8),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
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
