import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/admin_doujin_sync_check.dart';
import '../models/admin_stats.dart';
import '../models/admin_sync_run.dart';
import '../models/admin_sync_job.dart';
import '../models/admin_user.dart';
import '../models/event.dart';
import '../models/event_submission.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(apiClient: ref.watch(apiClientProvider));
});

class AdminRepository {
  AdminRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;
  static const _adminTimeout = Duration(seconds: 8);

  String get apiBaseUrl => _apiClient.baseUrl;

  Future<AdminStats> fetchStats() async {
    try {
      final response = await _apiClient
          .get('/admin/stats')
          .timeout(_adminTimeout);
      return AdminStats.fromJson(response.data as Map<String, dynamic>);
    } catch (error) {
      throw Exception('後台統計載入失敗：${_describeError(error)}');
    }
  }

  Future<List<CosEvent>> fetchEvents() async {
    try {
      final response = await _apiClient
          .get('/admin/events')
          .timeout(_adminTimeout);
      final rows = response.data as List<dynamic>;
      return rows
          .map((row) => CosEvent.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('活動資料載入失敗：${_describeError(error)}');
    }
  }

  Future<List<AdminUser>> fetchUsers() async {
    try {
      final response = await _apiClient
          .get('/admin/users')
          .timeout(_adminTimeout);
      final rows = response.data as List<dynamic>;
      return rows
          .map((row) => AdminUser.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('使用者資料載入失敗：${_describeError(error)}');
    }
  }

  Future<List<AdminSyncRun>> fetchSyncStatus() async {
    try {
      final response = await _apiClient
          .get('/admin/sync-status')
          .timeout(_adminTimeout);
      final rows = response.data as List<dynamic>;
      return rows
          .map((row) => AdminSyncRun.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('同步狀態載入失敗：${_describeError(error)}');
    }
  }

  Future<AdminDoujinSyncCheck> checkDoujinSync() async {
    try {
      final response = await _apiClient
          .get('/admin/doujin-sync-check')
          .timeout(const Duration(seconds: 24));
      return AdminDoujinSyncCheck.fromJson(
        response.data as Map<String, dynamic>,
      );
    } catch (error) {
      throw Exception('同步檢查載入失敗：${_describeError(error)}');
    }
  }

  Future<List<EventSubmission>> fetchSubmissions() async {
    try {
      final response = await _apiClient
          .get('/admin/event-submissions')
          .timeout(_adminTimeout);
      final rows = response.data as List<dynamic>;
      return rows
          .map((row) => EventSubmission.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('投稿資料載入失敗：${_describeError(error)}');
    }
  }

  Future<void> createEvent({
    required String category,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String venue,
    required String detailedAddress,
    required String fee,
    required String organizer,
    required String description,
    required String imageUrl,
    required String sourceUrl,
    required int sourceType,
    required String sourceName,
    required String status,
  }) async {
    await _apiClient.post(
      '/admin/events',
      data: {
        'category': category,
        'name': name,
        'startDate': _dateOnly(startDate),
        'endDate': _dateOnly(endDate),
        'venue': venue,
        'detailedAddress': detailedAddress,
        'fee': fee,
        'organizer': organizer,
        'description': description,
        'imageUrl': imageUrl,
        'sourceUrl': sourceUrl,
        'sourceType': sourceType,
        'sourceName': sourceName,
        'status': status,
      },
    );
  }

  Future<void> updateEvent({
    required String eventId,
    required String category,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String venue,
    required String detailedAddress,
    required String fee,
    required String organizer,
    required String description,
    required String imageUrl,
    required String sourceUrl,
    required int sourceType,
    required String sourceName,
    required String status,
  }) async {
    try {
      await _apiClient.put(
        '/admin/events/$eventId',
        data: {
          'category': category,
          'name': name,
          'startDate': _dateOnly(startDate),
          'endDate': _dateOnly(endDate),
          'venue': venue,
          'detailedAddress': detailedAddress,
          'fee': fee,
          'organizer': organizer,
          'description': description,
          'imageUrl': imageUrl,
          'sourceUrl': sourceUrl,
          'sourceType': sourceType,
          'sourceName': sourceName,
          'status': status,
        },
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        final code = (error.response?.data is Map)
            ? (error.response?.data as Map)['error']?.toString()
            : null;
        if (code == 'event_not_found') {
          throw Exception('找不到這筆活動，可能已被刪除，請重新整理活動列表');
        }
        throw Exception('後端尚未載入完整活動編輯 API，請重啟 backend 後再試');
      }
      rethrow;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    await _apiClient.delete('/admin/events/$eventId');
  }

  Future<void> updateEventDates({
    required String eventId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _apiClient.put(
      '/admin/events/$eventId/dates',
      data: {'startDate': _dateOnly(startDate), 'endDate': _dateOnly(endDate)},
    );
  }

  Future<void> deleteUser(String userId) async {
    await _apiClient.delete('/admin/users/$userId');
  }

  Future<void> updateUserStatus({
    required String userId,
    required String status,
  }) async {
    await _apiClient.put(
      '/admin/users/$userId/status',
      data: {'status': status},
    );
  }

  Future<void> updateUserAdmin({
    required String userId,
    required bool isAdmin,
  }) async {
    await _apiClient.put(
      '/admin/users/$userId/admin',
      data: {'isAdmin': isAdmin},
    );
  }

  Future<AdminSyncJob?> fetchSyncJob(String id) async {
    final response = await _apiClient.get('/admin/event-sync-jobs/$id');
    return response.data == null
        ? null
        : AdminSyncJob.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          );
  }

  Future<AdminSyncJob> syncDoujinEvents() async {
    try {
      final response = await _apiClient.post('/admin/sync-doujin-events');
      final data = response.data as Map<String, dynamic>;
      return AdminSyncJob.fromJson(data);
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

  String _describeError(Object error) {
    final base = 'API=${_apiClient.baseUrl}';
    try {
      if (error is TimeoutException) {
        return '連線逾時，請確認 backend 是否啟動。$base';
      }
      if (error is DioException) {
        final statusCode = error.response?.statusCode;
        if (statusCode != null) {
          return 'HTTP $statusCode。$base';
        }
        final detail = error.error?.toString();
        if (detail != null && detail.isNotEmpty) {
          return '${error.type.name}：$detail。$base';
        }
        return '${error.type.name}。$base';
      }
      return '$error。$base';
    } catch (_) {
      return '未知錯誤。$base';
    }
  }
}
