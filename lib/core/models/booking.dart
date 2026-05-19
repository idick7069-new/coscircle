enum ParticipantRole { photographer, coser, self }

class EventBooking {
  const EventBooking({
    required this.eventId,
    required this.role,
    this.characterName = '',
    this.workId,
    this.outfitImagePath,
    this.message = '',
  });

  final String eventId;
  final ParticipantRole role;
  final String characterName;
  final String? workId;
  final String? outfitImagePath;
  final String message;
}
