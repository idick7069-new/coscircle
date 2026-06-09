enum ParticipantRole { photographer, coser, manager, self }

class EventBooking {
  const EventBooking({
    required this.eventId,
    required this.role,
    this.dayIndex = 1,
    this.characterName = '',
    this.workId,
    this.outfitImagePath,
    this.interactionTags = const [],
    this.availableTime = '',
    this.presenceStatus = 'open',
    this.message = '',
  });

  final String eventId;
  final ParticipantRole role;
  final int dayIndex;
  final String characterName;
  final String? workId;
  final String? outfitImagePath;
  final List<String> interactionTags;
  final String availableTime;
  final String presenceStatus;
  final String message;
}
