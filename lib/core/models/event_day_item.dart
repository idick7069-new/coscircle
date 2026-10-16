import 'event.dart';
import '../utils/event_day_display.dart';

class EventDayItem {
  const EventDayItem({required this.event, required this.dayIndex});

  final CosEvent event;
  final int dayIndex;

  DateTime get date => event.startDate.add(Duration(days: dayIndex - 1));

  String get id => '${event.id}:$dayIndex';

  String get title => eventDayTitle(event, dayIndex);

  bool get isJoined => event.joinedDayIndexes.contains(dayIndex);
  bool get hasFollowedParticipants =>
      event.followedDayIndexes.contains(dayIndex);
  bool get hasCircleMembers => event.circleDayIndexes.contains(dayIndex);
  bool get hasFriends => event.friendDayIndexes.contains(dayIndex);

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
