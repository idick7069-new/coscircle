import 'event.dart';

class EventDayItem {
  const EventDayItem({required this.event, required this.dayIndex});

  final CosEvent event;
  final int dayIndex;

  DateTime get date => event.startDate.add(Duration(days: dayIndex - 1));

  String get id => '${event.id}:$dayIndex';

  String get title => '${event.name} D$dayIndex';

  bool get isJoined => event.isJoined;

  EventStatus status(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (today.isAfter(day)) return EventStatus.ended;
    if (today == day) return EventStatus.active;
    return EventStatus.upcoming;
  }
}

List<EventDayItem> expandEventDays(List<CosEvent> events) {
  return [
    for (final event in events)
      for (
        var dayIndex = 1;
        dayIndex <= event.endDate.difference(event.startDate).inDays + 1;
        dayIndex += 1
      )
        EventDayItem(event: event, dayIndex: dayIndex),
  ];
}
