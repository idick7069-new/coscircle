import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../config/app_environment.dart';
import '../models/booking_visibility.dart';
import '../models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (appDemoMode) return InMemoryProfileRepository();
  return ApiProfileRepository(apiClient: ref.watch(apiClientProvider));
});

abstract class ProfileRepository {
  Future<UserProfile?> currentProfile();
  Future<UserProfile?> fetchProfile(String publicCode);
  Future<void> followUser(String userId);
  Future<void> unfollowUser(String userId);
  Future<List<BookingFollowerGroup>> fetchBookingFollowers();
  Future<List<BlockedUser>> fetchBlockedUsers();
  Future<void> removeFollower(String userId);
  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);
  Future<UserProfile> saveProfile(UserProfile profile);
  Future<String> uploadImage({
    required Uint8List bytes,
    required String mimeType,
  });
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<UserProfile?> currentProfile() async {
    final response = await _apiClient.get('/me');
    final data = response.data;
    if (data == null) return null;
    return UserProfile.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<UserProfile?> fetchProfile(String publicCode) async {
    final response = await _apiClient.get('/profiles/$publicCode');
    final data = response.data;
    if (data == null) return null;
    return UserProfile.fromJson(data as Map<String, dynamic>);
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
  Future<List<BookingFollowerGroup>> fetchBookingFollowers() async {
    final response = await _apiClient.get('/me/booking-followers');
    final rows = response.data as List<dynamic>;
    return rows
        .map(
          (row) => BookingFollowerGroup.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> removeFollower(String userId) async {
    await _apiClient.delete('/me/followers/$userId');
  }

  @override
  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final response = await _apiClient.get('/blocked-users');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => BlockedUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> blockUser(String userId) async {
    await _apiClient.post('/users/$userId/block');
  }

  @override
  Future<void> unblockUser(String userId) async {
    await _apiClient.delete('/users/$userId/block');
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    try {
      if (kDebugMode) {
        debugPrint('[Profile] PUT /me avatarUrl=${profile.avatarUrl}');
      }
      final response = await _apiClient.put('/me', data: profile.toJson());
      if (kDebugMode) {
        debugPrint('[Profile] PUT /me success status=${response.statusCode}');
      }
      return UserProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Profile] PUT /me failed status=${error.response?.statusCode} '
          'body=${error.response?.data} message=${error.message}',
        );
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Profile] PUT /me unexpected error=$error');
      }
      rethrow;
    }
  }

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
          '[Profile] POST /uploads/image '
          'mimeType=$mimeType bytes=${bytes.length}',
        );
      }
      final response = await _apiClient.post(
        '/uploads/image',
        data: {'bytesBase64': base64Encode(bytes), 'mimeType': mimeType},
      );
      final url =
          (response.data as Map<String, dynamic>)['url']?.toString() ?? '';
      if (kDebugMode) {
        debugPrint(
          '[Profile] POST /uploads/image success '
          'status=${response.statusCode} url=$url',
        );
      }
      return url;
    } on DioException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Profile] POST /uploads/image failed '
          'status=${error.response?.statusCode} '
          'body=${error.response?.data} message=${error.message}',
        );
      }
      rethrow;
    }
  }
}

class InMemoryProfileRepository implements ProfileRepository {
  UserProfile? _profile = const UserProfile(id: 'me', nickname: '圈圈新朋友');

  @override
  Future<UserProfile?> currentProfile() async => _profile;

  @override
  Future<UserProfile?> fetchProfile(String publicCode) async {
    final profile = _profile;
    if (profile == null || profile.publicCode != publicCode) return null;
    return profile;
  }

  @override
  Future<void> followUser(String userId) async {}

  @override
  Future<void> unfollowUser(String userId) async {}

  @override
  Future<List<BookingFollowerGroup>> fetchBookingFollowers() async {
    return const [];
  }

  @override
  Future<void> removeFollower(String userId) async {}

  @override
  Future<List<BlockedUser>> fetchBlockedUsers() async {
    return const [];
  }

  @override
  Future<void> blockUser(String userId) async {}

  @override
  Future<void> unblockUser(String userId) async {}

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    _profile = profile;
    return profile;
  }

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    return '';
  }
}
