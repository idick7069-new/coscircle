class FeedPost {
  const FeedPost(this.data);
  final Map<String, dynamic> data;
  String text(String key) => data[key]?.toString() ?? '';
  bool flag(String key) => data[key] == true || data[key] == 1;
  int count(String key) => int.tryParse(text(key)) ?? 0;
  String get id => text('id');
  String get authorId => text('authorId');
  String get publicCode => text('publicCode');
  String get nickname => text('nickname');
  String get avatarUrl => text('avatarUrl');
  String get body => text('body');
  bool get isBooking => text('kind') == 'booking';
  bool get cancelled => flag('cancelled');
  bool get commentsEnabled => flag('commentsEnabled');
  bool get liked => flag('liked');
  bool get sameWork => flag('sameWork');
  String get visibility => text('visibility');
  List<String> get images =>
      (data['images'] as List? ?? []).map((e) => e.toString()).toList();
  Map<String, dynamic> toEditJson() => {
    'kind': text('kind'),
    'body': body,
    'visibility': visibility,
    'circleId': data['circleId'],
    'eventId': data['eventId'],
    'dayIndex': data['dayIndex'],
    'workId': data['workId'],
    'images': images,
    'commentsEnabled': commentsEnabled,
  };
}

class FeedResult {
  FeedResult.fromJson(Map<String, dynamic> json)
    : items = (json['items'] as List)
          .map((row) => FeedPost(Map<String, dynamic>.from(row as Map)))
          .toList(),
      nextCursor = json['nextCursor']?.toString();
  final List<FeedPost> items;
  final String? nextCursor;
}
