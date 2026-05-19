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

final selectedCurrentEventIdProvider =
    NotifierProvider<SelectedCurrentEventId, String?>(
      SelectedCurrentEventId.new,
    );

class SelectedCurrentEventId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String eventId) {
    state = eventId;
  }
}
