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
  Future<UserProfile?> fetchProfile(String userId);
  Future<UserProfile> saveProfile(UserProfile profile);
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
  Future<UserProfile?> fetchProfile(String userId) async {
    try {
      final response = await _apiClient.get('/users/$userId/profile');
      final data = response.data;
      if (data == null) return null;
      return UserProfile.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return _fallback.fetchProfile(userId);
    }
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    try {
      final response = await _apiClient.put('/me', data: profile.toJson());
      return UserProfile.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return _fallback.saveProfile(profile);
    }
  }
}

class InMemoryProfileRepository implements ProfileRepository {
  UserProfile? _profile = const UserProfile(id: 'me', nickname: '圈圈新朋友');

  @override
  Future<UserProfile?> currentProfile() async => _profile;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    final profile = _profile;
    if (profile == null || profile.id != userId) return null;
    return profile;
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    _profile = profile;
    return profile;
  }
}
