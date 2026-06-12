import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ApiProfileRepository(
    apiClient: ref.watch(apiClientProvider),
    fallback: InMemoryProfileRepository(),
  );
});

abstract class ProfileRepository {
  Future<UserProfile?> currentProfile();
  Future<UserProfile?> fetchProfile(String publicCode);
  Future<void> followUser(String userId);
  Future<void> unfollowUser(String userId);
  Future<UserProfile> saveProfile(UserProfile profile);
  Future<String> uploadImage({
    required Uint8List bytes,
    required String mimeType,
  });
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({
    required ApiClient apiClient,
    required ProfileRepository fallback,
  }) : _apiClient = apiClient,
       _fallback = fallback;

  final ApiClient _apiClient;
  final ProfileRepository _fallback;

  @override
  Future<UserProfile?> currentProfile() async {
    try {
      final response = await _apiClient.get('/me');
      final data = response.data;
      if (data == null) return null;
      return UserProfile.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return _fallback.currentProfile();
    }
  }

  @override
  Future<UserProfile?> fetchProfile(String publicCode) async {
    try {
      final response = await _apiClient.get('/profiles/$publicCode');
      final data = response.data;
      if (data == null) return null;
      return UserProfile.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return _fallback.fetchProfile(publicCode);
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
        return _fallback.saveProfile(profile);
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Profile] PUT /me unexpected error=$error');
        return _fallback.saveProfile(profile);
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
