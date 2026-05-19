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

  Future<void> createCircle(String name) async {
    await _apiClient.post('/circles', data: {'name': name});
  }

  Future<void> joinCircle(String invite) async {
    await _apiClient.post('/circles/join', data: {'invite': invite});
  }

  Future<void> leaveCircle(String circleId) async {
    await _apiClient.delete('/circles/$circleId/members/me');
  }
}
