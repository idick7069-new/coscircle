import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/admin_stats.dart';
import '../models/event.dart';
import '../models/event_submission.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(apiClient: ref.watch(apiClientProvider));
});

class AdminRepository {
  AdminRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AdminStats> fetchStats() async {
    final response = await _apiClient.get('/admin/stats');
    return AdminStats.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<CosEvent>> fetchEvents() async {
    final response = await _apiClient.get('/admin/events');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => CosEvent.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<EventSubmission>> fetchSubmissions() async {
    final response = await _apiClient.get('/admin/event-submissions');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => EventSubmission.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createEvent({
    required String category,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String venue,
    required String fee,
    required String organizer,
    required String description,
  }) async {
    await _apiClient.post(
      '/admin/events',
      data: {
        'category': category,
        'name': name,
        'startDate': _dateOnly(startDate),
        'endDate': _dateOnly(endDate),
        'venue': venue,
        'fee': fee,
        'organizer': organizer,
        'description': description,
      },
    );
  }

  Future<void> deleteEvent(String eventId) async {
    await _apiClient.delete('/admin/events/$eventId');
  }

  Future<int> syncDoujinEvents() async {
    try {
      final response = await _apiClient.post('/admin/sync-doujin-events');
      final data = response.data as Map<String, dynamic>;
      return int.tryParse(data['count'].toString()) ?? 0;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw Exception('後端尚未載入手動同步 API，請重啟 backend 後再試');
      }
      rethrow;
    }
  }

  Future<void> approveSubmission(String submissionId) async {
    await _apiClient.post('/admin/event-submissions/$submissionId/approve');
  }

  Future<void> rejectSubmission(String submissionId) async {
    await _apiClient.post('/admin/event-submissions/$submissionId/reject');
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
