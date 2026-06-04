import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/circle.dart';

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SocialRepository(apiClient: ref.watch(apiClientProvider));
});

class SocialRepository {
  SocialRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

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
