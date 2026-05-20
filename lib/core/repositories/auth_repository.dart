import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(apiClient: ref.watch(apiClientProvider));
});

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token']?.toString() ?? '',
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class AuthRepository {
  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  static const _tokenKey = 'auth_token';

  final ApiClient _apiClient;

  Future<String?> restoreToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    _apiClient.setAuthToken(token);
    try {
      await _apiClient.get('/me');
      return token;
    } catch (_) {
      await prefs.remove(_tokenKey);
      _apiClient.setAuthToken(null);
      return null;
    }
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _authenticate(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    await _saveToken(session.token);
    return session;
  }

  Future<AuthSession> register({
    required String nickname,
    required String email,
    required String password,
  }) async {
    final session = await _authenticate(
      '/auth/register',
      data: {'nickname': nickname, 'email': email, 'password': password},
    );
    await _saveToken(session.token);
    return session;
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout');
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      _apiClient.setAuthToken(null);
    }
  }

  Future<AuthSession> _authenticate(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final response = await _apiClient.post(path, data: data);
    return AuthSession.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _apiClient.setAuthToken(token);
  }
}
