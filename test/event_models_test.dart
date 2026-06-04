import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/models/shared_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EventParticipant parses public profile and cosplay fields', () {
    final participant = EventParticipant.fromJson({
      'userId': 12,
      'publicCode': 'abc123',
      'nickname': '阿月',
      'role': 'coser',
      'avatarUrl': 'https://example.com/avatar.jpg',
      'workId': 4,
      'workName': '葬送的芙莉蓮',
      'characterName': '芙莉蓮',
      'outfitImageUrl': 'https://example.com/outfit.jpg',
      'interactionTags': '認親, 拍照',
      'isMe': 0,
      'isFollowed': 1,
    });

    expect(participant.userId, '12');
    expect(participant.publicCode, 'abc123');
    expect(participant.workName, '葬送的芙莉蓮');
    expect(participant.characterName, '芙莉蓮');
    expect(participant.interactionTags, ['認親', '拍照']);
    expect(participant.isFollowed, isTrue);
  });

  test('SharedLocation parses public code and event presence metadata', () {
    final location = SharedLocation.fromJson({
      'userId': 12,
      'publicCode': 'abc123',
      'nickname': '阿月',
      'role': 'manager',
      'latitude': '25.033',
      'longitude': '121.565',
      'sharedAt': '2026-06-02T13:00:00',
      'workName': '作品名',
      'characterName': '角色名',
      'interactionTags': ['聊天', '一起逛'],
      'isCircleMember': 1,
    });

    expect(location.publicCode, 'abc123');
    expect(location.role, 'manager');
    expect(location.latitude, 25.033);
    expect(location.longitude, 121.565);
    expect(location.interactionTags, ['聊天', '一起逛']);
    expect(location.isCircleMember, isTrue);
  });
}
