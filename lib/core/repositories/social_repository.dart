import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/circle.dart';
import '../models/friendship.dart';

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SocialRepository(apiClient: ref.watch(apiClientProvider));
});

class SocialRepository {
  SocialRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Friendship>> fetchFriendships() async {
    final response = await _apiClient.get('/friends');
    return (response.data as List<dynamic>)
        .map((row) => Friendship.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> inviteFriend(
    String userId, {
    required String introduction,
    String? eventId,
    int? dayIndex,
  }) async {
    final response = await _apiClient.post(
      '/friend-invites/$userId',
      data: {
        'introduction': introduction,
        if (eventId != null) 'eventId': eventId,
        if (eventId != null) 'dayIndex': dayIndex,
      },
    );
    return (response.data as Map<String, dynamic>)['status'].toString();
  }

  Future<void> respondFriend(String requestId, {required bool accept}) async {
    await _apiClient.post(
      '/friend-requests/$requestId/respond',
      data: {'action': accept ? 'accept' : 'ignore'},
    );
  }

  Future<void> removeFriend(String userId) async {
    await _apiClient.delete('/friends/$userId');
  }

  Future<List<CircleGroup>> fetchCircles() async {
    final response = await _apiClient.get('/circles');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => CircleGroup.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<FollowedUser>> fetchFollowing() async {
    final response = await _apiClient.get('/following');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => FollowedUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCircle(String name, {String description = ''}) async {
    await _apiClient.post(
      '/circles',
      data: {'name': name, 'description': description},
    );
  }

  Future<void> updateCircle({
    required String circleId,
    required String name,
    required String description,
  }) async {
    await _apiClient.put(
      '/circles/$circleId',
      data: {'name': name, 'description': description},
    );
  }

  Future<void> joinCircle(String invite) async {
    await _apiClient.post('/circles/join', data: {'invite': invite});
  }

  Future<void> leaveCircle(String circleId) async {
    await _apiClient.delete('/circles/$circleId/members/me');
  }

  Future<void> dissolveCircle(String circleId) async {
    await _apiClient.delete('/circles/$circleId');
  }

  Future<void> removeCircleMember({
    required String circleId,
    required String userId,
  }) async {
    await _apiClient.delete('/circles/$circleId/members/$userId');
  }

  Future<void> unfollowUser(String userId) async {
    await _apiClient.delete('/users/$userId/follow');
  }
}
