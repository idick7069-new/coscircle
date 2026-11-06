import 'work.dart';

class SameWorkUser {
  const SameWorkUser({
    required this.userId,
    required this.publicCode,
    required this.nickname,
    required this.commonWorks,
    this.avatarUrl = '',
    this.bio = '',
    required this.commonWorkCount,
  });

  final String userId;
  final String publicCode;
  final String nickname;
  final String avatarUrl;
  final String bio;
  final int commonWorkCount;
  final List<WorkTag> commonWorks;

  factory SameWorkUser.fromJson(Map<String, dynamic> json) => SameWorkUser(
    userId: json['userId'].toString(),
    publicCode: json['publicCode']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? '',
    avatarUrl: json['avatarUrl']?.toString() ?? '',
    bio: json['bio']?.toString() ?? '',
    commonWorkCount: int.tryParse(json['commonWorkCount'].toString()) ?? 0,
    commonWorks: (json['commonWorks'] as List<dynamic>? ?? [])
        .map((item) => WorkTag.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class SameWorkPage {
  const SameWorkPage({required this.items, this.nextOffset});

  final List<SameWorkUser> items;
  final int? nextOffset;

  factory SameWorkPage.fromJson(Map<String, dynamic> json) => SameWorkPage(
    items: (json['items'] as List<dynamic>)
        .map((item) => SameWorkUser.fromJson(item as Map<String, dynamic>))
        .toList(),
    nextOffset: json['hasMore'] == true
        ? int.tryParse(json['nextOffset'].toString())
        : null,
  );
}
