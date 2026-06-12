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
        error: (error, stack) =>
            Center(child: Text('活動載入失敗：${userFacingError(error)}')),
        loading: () => const Center(child: CircularProgressIndicator()),
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
                    ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => _updateFilters(filter: filter),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilterChip(
                    avatar: Icon(
                      _hideEnded
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                    ),
                    label: const Text('隱藏已結束'),
                    selected: _hideEnded,
                    onSelected: (value) => _updateFilters(hideEnded: value),
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
      builder: (context) =>
          BookingSheet(event: event, initialDayIndex: dayIndex),
    );
  }

  Future<void> _refreshEvents() async {
    ref.invalidate(eventParticipantsProvider);
    await Future.wait([ref.refresh(eventsProvider.future)]);
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

    final mediaQuery = MediaQuery.of(context);

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.86),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Row(
                children: [
                  const CosIconBubble(icon: Icons.badge_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.initialParticipant != null
                              ? '修改出角預訂'
                              : '發布出角預訂',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '讓同好知道你會去、當天扮什麼、以及歡迎怎麼互動。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('參加日', style: Theme.of(context).textTheme.titleSmall),
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
                          ChoiceChip(
                            label: Text('D$index'),
                            avatar: const Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                            ),
                            selected: _dayIndex == index,
                            onSelected: (_) =>
                                setState(() => _dayIndex = index),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ParticipantRole>(
                      segments: const [
                        ButtonSegment(
                          value: ParticipantRole.photographer,
                          label: Text('攝影'),
                          icon: Icon(Icons.camera_alt),
                        ),
                        ButtonSegment(
                          value: ParticipantRole.coser,
                          label: Text('Coser'),
                          icon: Icon(Icons.face),
                        ),
                        ButtonSegment(
                          value: ParticipantRole.manager,
                          label: Text('馬內'),
                          icon: Icon(Icons.support_agent),
                        ),
                        ButtonSegment(
                          value: ParticipantRole.self,
                          label: Text('路人'),
                          icon: Icon(Icons.person),
                        ),
                      ],
                      selected: {_role},
                      onSelectionChanged: (value) =>
                          setState(() => _role = value.first),
                    ),
                  ],
                ),
              ),
              if (_role == ParticipantRole.coser) ...[
                const SizedBox(height: 12),
                WorkSingleSelector(
                  label: '作品',
                  selected: _selectedWork,
                  onChanged: (work) => setState(() => _selectedWork = work),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _characterController,
                  decoration: const InputDecoration(labelText: '角色名'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _availableTimeController,
                decoration: const InputDecoration(
                  labelText: '預計出沒時間',
                  hintText: '例如 13:00 - 16:00、午後、整天',
                ),
              ),
              const SizedBox(height: 12),
              Text('歡迎互動方式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _interactionOptions)
                    FilterChip(
                      label: Text(option),
                      selected: _interactionTags.contains(option),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _interactionTags.add(option);
                          } else {
                            _interactionTags.remove(option);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _presenceStatus,
                decoration: const InputDecoration(labelText: '現場狀態'),
                items: [
                  for (final option in _statusOptions)
                    DropdownMenuItem(value: option.$1, child: Text(option.$2)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _presenceStatus = value);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickOutfitImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_outfitImagePath == null ? '當天長這樣' : '已選擇照片'),
              ),
              if (_outfitImagePath != null) ...[
                const SizedBox(height: 8),
                Text(
                  _outfitImagePath!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: '備註',
                  hintText: '例如 看到我可以打招呼、社恐請先私訊',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.initialParticipant != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => _removeAttendance(context, event),
                        child: const Text('取消出席'),
                      ),
                    ),
                  if (widget.initialParticipant != null)
                    const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting
                          ? null
                          : () => _saveAttendance(context, event),
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              widget.initialParticipant != null
                                  ? '儲存出席'
                                  : '我會去',
                            ),
                    ),
                  ),
                ],
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
}
