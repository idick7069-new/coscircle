import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../models/feed_post.dart';

final feedRevisionProvider = Provider<Object>((ref) => Object());

final feedSessionProvider = Provider<int>((ref) {
  final api = ref.watch(apiClientProvider);
  void changed() => ref.invalidateSelf();
  api.sessionChanges.addListener(changed);
  ref.onDispose(() => api.sessionChanges.removeListener(changed));
  return api.sessionVersion;
});
final feedRepositoryProvider = Provider(
  (ref) => FeedRepository(ref.watch(apiClientProvider)),
);
final feedPostProvider = FutureProvider.autoDispose.family<FeedPost, String>((
  ref,
  id,
) {
  ref.watch(feedSessionProvider);
  ref.watch(feedRevisionProvider);
  return ref.watch(feedRepositoryProvider).detail(id);
});
final feedNotificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      ref.watch(feedSessionProvider);
      ref.watch(feedRevisionProvider);
      return ref.watch(feedRepositoryProvider).notifications();
    });

class FeedRepository {
  FeedRepository(this.api);
  final ApiClient api;
  Future<FeedResult> list({
    String kind = 'all',
    String scope = 'all',
    String? eventId,
    String? before,
  }) async {
    final r = await api.get(
      '/feed',
      query: {
        'kind': kind,
        'scope': scope,
        if (eventId != null) 'eventId': eventId,
        if (before != null) 'before': before,
      },
    );
    return FeedResult.fromJson(Map<String, dynamic>.from(r.data as Map));
  }

  Future<FeedPost> detail(String id) async => FeedPost(
    Map<String, dynamic>.from((await api.get('/feed/$id')).data as Map),
  );
  Future<String> save(Map<String, dynamic> body, {String? id}) async {
    final r = id == null
        ? await api.post('/feed', data: body)
        : await api.put('/feed/$id', data: body);
    return (r.data as Map)['id'].toString();
  }

  Future<void> remove(String id) async => api.delete('/feed/$id');
  Future<void> like(String id, bool enabled) async {
    if (enabled) {
      await api.put('/feed/$id/like');
    } else {
      await api.delete('/feed/$id/like');
    }
  }

  Future<Map<String, dynamic>> comments(String id, {String? before}) async =>
      Map<String, dynamic>.from(
        (await api.get(
              '/feed/$id/comments',
              query: {if (before != null) 'before': before},
            )).data
            as Map,
      );
  Future<void> comment(String id, String body, {String? parentId}) async =>
      api.post(
        '/feed/$id/comments',
        data: {'body': body, if (parentId != null) 'parentId': parentId},
      );
  Future<void> removeComment(String id, String commentId) async =>
      api.delete('/feed/$id/comments/$commentId');
  Future<List<Map<String, dynamic>>> notifications() async =>
      ((await api.get('/feed/notifications')).data as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
  Future<void> readNotification(String id) async =>
      api.post('/feed/notifications/$id/read');
  Future<void> report(
    String id, {
    required String reason,
    String details = '',
    String? commentId,
  }) async => api.post(
    '/feed/$id/reports',
    data: {
      'reason': reason,
      'details': details,
      if (commentId != null) 'commentId': commentId,
    },
  );
  Future<Map<String, dynamic>?> bookingShare(
    String eventId,
    int dayIndex,
  ) async {
    final r = await api.get(
      '/feed/booking-share',
      query: {'eventId': eventId, 'dayIndex': dayIndex},
    );
    return r.data == null ? null : Map<String, dynamic>.from(r.data as Map);
  }
}
