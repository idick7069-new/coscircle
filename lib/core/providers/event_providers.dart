import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/participant.dart';
import '../repositories/event_repository.dart';

final eventsProvider = FutureProvider.autoDispose<List<CosEvent>>((ref) {
  return ref.watch(eventRepositoryProvider).fetchEvents();
});

final eventParticipantsProvider = FutureProvider.autoDispose
    .family<List<EventParticipant>, String>((ref, eventId) {
      return ref.watch(eventRepositoryProvider).fetchParticipants(eventId);
    });

final selectedCurrentEventTargetProvider =
    NotifierProvider<SelectedCurrentEventTargetController, CurrentEventTarget?>(
      SelectedCurrentEventTargetController.new,
    );

class CurrentEventTarget {
  const CurrentEventTarget({required this.eventId, required this.dayIndex});

  final String eventId;
  final int dayIndex;
}

class SelectedCurrentEventTargetController
    extends Notifier<CurrentEventTarget?> {
  @override
  CurrentEventTarget? build() => null;

  void select(String eventId, {int dayIndex = 1}) {
    state = CurrentEventTarget(eventId: eventId, dayIndex: dayIndex);
  }
}
