import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/work.dart';

final workRepositoryProvider = Provider<WorkRepository>((ref) {
  return ApiWorkRepository(apiClient: ref.watch(apiClientProvider));
});

abstract class WorkRepository {
  Future<List<WorkTag>> searchWorks(String query);
  Future<WorkTag> createWork(String name);
}

class ApiWorkRepository implements WorkRepository {
  ApiWorkRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<List<WorkTag>> searchWorks(String query) async {
    final response = await _apiClient.get('/works', query: {'query': query});
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => WorkTag.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<WorkTag> createWork(String name) async {
    final response = await _apiClient.post('/works', data: {'name': name});
    return WorkTag.fromJson(response.data as Map<String, dynamic>);
  }
}
