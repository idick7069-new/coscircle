import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/booking.dart';
import '../models/event.dart';
import '../models/participant.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return ApiEventRepository(
    apiClient: ref.watch(apiClientProvider),
    fallback: InMemoryEventRepository(),
  );
});

abstract class EventRepository {
  Future<List<CosEvent>> fetchEvents();
  Future<List<EventParticipant>> fetchParticipants(String eventId);
  Future<void> followUser(String userId);
  Future<void> unfollowUser(String userId);
  Future<void> blockUser(String userId);
  Future<void> upsertBooking(EventBooking booking);
  Future<void> removeBooking(String eventId, {int? dayIndex});
}

class ApiEventRepository implements EventRepository {
  ApiEventRepository({
    required ApiClient apiClient,
    required EventRepository fallback,
  }) : _apiClient = apiClient,
       _fallback = fallback;

  final ApiClient _apiClient;
  final EventRepository _fallback;

  @override
  Future<List<CosEvent>> fetchEvents() async {
    try {
      final response = await _apiClient.get('/events');
      final rows = response.data as List<dynamic>;
      return rows
          .map((row) => CosEvent.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      if (kDebugMode) return _fallback.fetchEvents();
      rethrow;
    }
  }

  @override
  Future<List<EventParticipant>> fetchParticipants(String eventId) async {
    try {
      final response = await _apiClient.get('/events/$eventId/participants');
      final rows = response.data as List<dynamic>;
      return rows
          .map((row) => EventParticipant.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      if (kDebugMode) return _fallback.fetchParticipants(eventId);
      rethrow;
    }
  }

  @override
  Future<void> followUser(String userId) async {
    await _apiClient.post('/users/$userId/follow');
  }

  @override
  Future<void> unfollowUser(String userId) async {
    await _apiClient.delete('/users/$userId/follow');
  }

  @override
  Future<void> blockUser(String userId) async {
    await _apiClient.post('/users/$userId/block');
  }

  @override
  Future<void> upsertBooking(EventBooking booking) async {
    try {
      await _apiClient.post(
        '/events/${booking.eventId}/bookings',
        data: {
          'role': booking.role.name,
          'dayIndex': booking.dayIndex,
          'characterName': booking.characterName,
          'workId': booking.workId,
          'outfitImageUrl': booking.outfitImagePath,
          'interactionTags': booking.interactionTags,
          'availableTime': booking.availableTime,
          'presenceStatus': booking.presenceStatus,
          'message': booking.message,
        },
      );
    } catch (_) {
      if (kDebugMode) {
        await _fallback.upsertBooking(booking);
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> removeBooking(String eventId, {int? dayIndex}) async {
    try {
      await _apiClient.delete(
        '/events/$eventId/bookings/me',
        query: dayIndex == null ? null : {'dayIndex': dayIndex},
      );
    } catch (_) {
      if (kDebugMode) {
        await _fallback.removeBooking(eventId, dayIndex: dayIndex);
        return;
      }
      rethrow;
    }
  }
}

class InMemoryEventRepository implements EventRepository {
  final Map<String, EventBooking> _bookings = {};

  @override
  Future<List<CosEvent>> fetchEvents() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _seedEvents
        .map(
          (event) => event.copyWith(isJoined: _bookings.containsKey(event.id)),
        )
        .toList();
  }

  @override
  Future<List<EventParticipant>> fetchParticipants(String eventId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _seedParticipants[eventId] ?? const [];
  }

  @override
  Future<void> followUser(String userId) async {}

  @override
  Future<void> unfollowUser(String userId) async {}

  @override
  Future<void> blockUser(String userId) async {}

  @override
  Future<void> upsertBooking(EventBooking booking) async {
    _bookings[booking.eventId] = booking;
  }

  @override
  Future<void> removeBooking(String eventId, {int? dayIndex}) async {
    if (dayIndex == null) {
      _bookings.remove(eventId);
      return;
    }
    final booking = _bookings[eventId];
    if (booking?.dayIndex == dayIndex) _bookings.remove(eventId);
  }
}

final _seedEvents = <CosEvent>[
  CosEvent(
    id: 'ncf-2026',
    name: 'NCF成大琥珀月同人誌展',
    category: '綜合',
    startDate: DateTime(2026, 5, 23),
    endDate: DateTime(2026, 5, 24),
    venue: '國立成功大學光復校區',
    detailedAddress: '台南市東區大學路1號',
    fee: '免費',
    organizer: '國立成功大學漫畫社',
    description: '同人誌展、ACG交流與 Cosplay 同樂活動。',
    imageUrl:
        'https://images.unsplash.com/photo-1511512578047-dfb367046420?w=900',
    sourceType: 1,
    sourceName: '同人誌中心',
    sourceUrl: 'https://www.doujin.com.tw/events/alist',
    hasCircleMembers: true,
  ),
  CosEvent(
    id: 'if7-2026',
    name: 'IF7創集繪 同人誌販售會',
    category: '綜合',
    startDate: DateTime(2026, 5, 30),
    endDate: DateTime(2026, 5, 30),
    venue: '花博公園 爭艷館',
    detailedAddress: '台北市中山區玉門街1號',
    fee: '未定',
    organizer: 'GJ工作室',
    description: '大型同人誌販售會。',
    imageUrl:
        'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=900',
    sourceType: 1,
    sourceName: '同人誌中心',
    sourceUrl: 'https://www.doujin.com.tw/events/alist',
    hasFollowedParticipants: true,
  ),
  CosEvent(
    id: 'bio13-2026',
    name: 'Bring It On！歐美主題ONLY場 BIO13',
    category: 'PT ONLY',
    startDate: DateTime(2026, 5, 30),
    endDate: DateTime(2026, 5, 30),
    venue: '花博公園 爭艷館',
    detailedAddress: '台北市中山區玉門街1號',
    fee: '未定',
    organizer: 'GJ工作室',
    description: '歐美主題 ONLY 場。',
    imageUrl:
        'https://images.unsplash.com/photo-1517457373958-b7bdd4587205?w=900',
    sourceType: 2,
    sourceName: '投稿活動',
    sourceUrl: '',
  ),
  CosEvent(
    id: 'furrymosa8-2026',
    name: 'Furrymosa 8 -獸系ONLY同人誌販售會-',
    category: 'ONLY',
    startDate: DateTime(2026, 6, 6),
    endDate: DateTime(2026, 6, 6),
    venue: '三重綜合體育館',
    detailedAddress: '新北市三重區新北大道一段2號',
    fee: '200元',
    organizer: 'Furrymosa執行小組',
    description: '獸系 ONLY 同人誌販售會。',
    imageUrl:
        'https://images.unsplash.com/photo-1505373877841-8d25f7d46678?w=900',
    sourceType: 2,
    sourceName: '投稿活動',
    sourceUrl: '',
  ),
  CosEvent(
    id: 'liuli-code002-2026',
    name: '〖琉璃動漫市集〗高雄社教館code002',
    category: '綜合',
    startDate: DateTime(2026, 7, 4),
    endDate: DateTime(2026, 7, 5),
    venue: '高雄市社教館綜合體育館',
    detailedAddress: '高雄市小港區學府路115號',
    fee: '免費',
    organizer: '琉璃市集',
    description: '動漫週邊、創作者育成、文創市集、玩具收藏與 Cosplay 同樂區。',
    imageUrl:
        'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=900',
    sourceType: 1,
    sourceName: '同人誌中心',
    sourceUrl: 'https://www.doujin.com.tw/events/alist',
  ),
];

final _seedParticipants = <String, List<EventParticipant>>{
  'ncf-2026': [
    EventParticipant(
      userId: 'u1',
      nickname: '小夏',
      role: 'coser',
      characterName: '瑪琳',
      outfitImageUrl:
          'https://images.unsplash.com/photo-1529139574466-a303027c1d8b?w=700',
      interactionTags: ['認親', '拍照', '交換無料'],
      availableTime: '13:00 - 16:00',
      presenceStatus: 'open',
      message: '下午會在光復校區周邊出沒。',
      isFollowed: true,
    ),
    EventParticipant(
      userId: 'u2',
      nickname: '阿哲',
      role: 'photographer',
      interactionTags: ['拍照', '聊天'],
      availableTime: '午後',
      message: '可協助合照。',
    ),
    EventParticipant(userId: 'u3', nickname: 'Rin', role: 'self', isMe: true),
  ],
  'if7-2026': [
    EventParticipant(
      userId: 'u4',
      nickname: 'Mika',
      role: 'coser',
      characterName: '初音',
      isFollowed: true,
    ),
    EventParticipant(userId: 'u5', nickname: 'Nora', role: 'self'),
    EventParticipant(userId: 'u6', nickname: 'Kai', role: 'photographer'),
    EventParticipant(userId: 'u7', nickname: 'Yui', role: 'manager'),
  ],
};
