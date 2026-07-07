import '../models/event.dart';

int eventDayCount(CosEvent event) {
  return event.endDate.difference(event.startDate).inDays + 1;
}

String eventDisplayName(CosEvent event) {
  return event.name
      .replaceAll(RegExp(r'\s*New!!\s*$', caseSensitive: false), '')
      .trim();
}

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
