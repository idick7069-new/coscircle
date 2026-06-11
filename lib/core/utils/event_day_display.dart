import '../models/event.dart';

int eventDayCount(CosEvent event) {
  return event.endDate.difference(event.startDate).inDays + 1;
}

String eventDayTitle(CosEvent event, int dayIndex) {
  if (eventDayCount(event) <= 1) return event.name;
  return '${event.name} D$dayIndex';
}

String currentEventTitle(CosEvent event, int dayIndex) {
  if (eventDayCount(event) <= 1) return event.name;
  return '${event.name} D$dayIndex';
}
