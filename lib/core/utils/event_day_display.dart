import '../models/event.dart';

int eventDayCount(CosEvent event) {
  return event.endDate.difference(event.startDate).inDays + 1;
}

String cleanEventName(String name) {
  return name
      .replaceAll(RegExp(r'\s*New!!\s*$', caseSensitive: false), '')
      .trim();
}

String eventDisplayName(CosEvent event) => cleanEventName(event.name);

String eventDayTitle(CosEvent event, int dayIndex) {
  final name = eventDisplayName(event);
  if (eventDayCount(event) <= 1) return name;
  return '$name D$dayIndex';
}

String currentEventTitle(CosEvent event, int dayIndex) {
  final name = eventDisplayName(event);
  if (eventDayCount(event) <= 1) return name;
  return '$name D$dayIndex';
}
