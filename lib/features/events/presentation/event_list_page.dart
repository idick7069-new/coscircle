import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/booking.dart';
import '../../../core/models/event.dart';
import '../../../core/models/work.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/event_repository.dart';
import '../../works/presentation/work_selector.dart';
import 'widgets/event_card.dart';

class EventListPage extends ConsumerStatefulWidget {
  const EventListPage({super.key, required this.onOpenCurrentEvent});

  final ValueChanged<CosEvent> onOpenCurrentEvent;

  @override
  ConsumerState<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends ConsumerState<EventListPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _joinedOnly = false;
  bool _hideEnded = false;
  String _filter = '全部';

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(eventsProvider),
      child: events.when(
        data: (items) {
          final filtered = _applyFilters(items);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '活動清單',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: '只看我參加',
                        isSelected: _joinedOnly,
                        onPressed: () =>
                            setState(() => _joinedOnly = !_joinedOnly),
                        icon: const Icon(Icons.how_to_reg),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _calendar(items)),
              SliverToBoxAdapter(child: _filterChips()),
              SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final event = filtered[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: EventCard(
                      event: event,
                      onTap: event.status(DateTime.now()) == EventStatus.active
                          ? () => widget.onOpenCurrentEvent(event)
                          : null,
                      onBookingPressed:
                          event.status(DateTime.now()) == EventStatus.ended
                          ? null
                          : () => _showBookingSheet(context, event),
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
        error: (error, stack) => Center(child: Text('活動載入失敗：$error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _calendar(List<CosEvent> events) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TableCalendar<CosEvent>(
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
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary,
                        shape: BoxShape.circle,
                        border: event.isJoined
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onPrimary,
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
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        calendarStyle: CalendarStyle(
          markerDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    final filters = ['全部', '我有加入', '關注者', '小圈圈'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in filters)
            ChoiceChip(
              label: Text(filter),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
            ),
          FilterChip(
            avatar: Icon(
              _hideEnded ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
            ),
            label: const Text('隱藏已結束'),
            selected: _hideEnded,
            onSelected: (value) => setState(() => _hideEnded = value),
          ),
        ],
      ),
    );
  }

  List<CosEvent> _applyFilters(List<CosEvent> events) {
    return events.where((event) {
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
          !_hideEnded || event.status(DateTime.now()) != EventStatus.ended;
      return matchesDate && matchesJoined && matchesType && matchesEnded;
    }).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Future<void> _showBookingSheet(BuildContext context, CosEvent event) async {
    if (event.status(DateTime.now()) == EventStatus.ended) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BookingSheet(event: event),
    );
  }
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({required this.event});

  final CosEvent event;

  @override
  ConsumerState<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<_BookingSheet> {
  ParticipantRole _role = ParticipantRole.coser;
  final _characterController = TextEditingController();
  final _messageController = TextEditingController();
  String? _outfitImagePath;
  WorkTag? _selectedWork;

  @override
  void dispose() {
    _characterController.dispose();
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
              Text(
                event.isJoined ? '修改預訂' : '新增預訂',
                style: Theme.of(context).textTheme.titleLarge,
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
                    value: ParticipantRole.self,
                    label: Text('本體'),
                    icon: Icon(Icons.person),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (value) =>
                    setState(() => _role = value.first),
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
              OutlinedButton.icon(
                onPressed: _pickOutfitImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_outfitImagePath == null ? '上傳當天預計穿著' : '已選擇當天穿著'),
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
                decoration: const InputDecoration(labelText: '想說的話'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (event.isJoined)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await ref
                              .read(eventRepositoryProvider)
                              .removeBooking(event.id);
                          ref.invalidate(eventsProvider);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('移除預訂'),
                      ),
                    ),
                  if (event.isJoined) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await ref
                            .read(eventRepositoryProvider)
                            .upsertBooking(
                              EventBooking(
                                eventId: event.id,
                                role: _role,
                                workId: _role == ParticipantRole.coser
                                    ? _selectedWork?.id
                                    : null,
                                characterName: _characterController.text,
                                outfitImagePath: _outfitImagePath,
                                message: _messageController.text,
                              ),
                            );
                        ref.invalidate(eventsProvider);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(event.isJoined ? '儲存修改' : '加入活動'),
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
    setState(() => _outfitImagePath = image.path);
  }
}
