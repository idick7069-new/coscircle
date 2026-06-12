import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(apiClient: ref.watch(apiClientProvider));
});

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    this.isNewUser = false,
  });

  final String token;
  final UserProfile user;
  final bool isNewUser;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token']?.toString() ?? '',
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      isNewUser: json['isNewUser'] == true || json['isNewUser'] == 1,
    );
  }
}

enum SocialLoginProvider {
  facebook('facebook', 'Facebook'),
  line('line', 'LINE');

  const SocialLoginProvider(this.apiValue, this.label);

  final String apiValue;
  final String label;
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
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode != 401 && statusCode != 403) return token;
      await prefs.remove(_tokenKey);
      _apiClient.setAuthToken(null);
      return null;
    } catch (_) {
      return token;
    }
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    _logAuthAttempt('login', email);
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
    _logAuthAttempt('register', email);
    final session = await _authenticate(
      '/auth/register',
      data: {'nickname': nickname, 'email': email, 'password': password},
    );
    await _saveToken(session.token);
    return session;
  }

  Future<AuthSession> socialLogin({
    required SocialLoginProvider provider,
    required String accessToken,
  }) async {
    final session = await _authenticate(
      '/auth/social',
      data: {'provider': provider.apiValue, 'accessToken': accessToken},
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
    try {
      final response = await _apiClient.post(path, data: data);
      if (kDebugMode) {
        debugPrint(
          '[Auth] $path success status=${response.statusCode} '
          'email=${_safeEmail(data['email'])}',
        );
      }
      return AuthSession.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error, stackTrace) {
      final response = error.response;
      if (kDebugMode) {
        debugPrint(
          '[Auth] $path failed '
          'email=${_safeEmail(data['email'])} '
          'type=${error.type} '
          'status=${response?.statusCode} '
          'message=${error.message} '
          'body=${response?.data}',
        );
        debugPrintStack(stackTrace: stackTrace, label: '[Auth] DioException');
      }
      rethrow;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[Auth] $path unexpected error '
          'email=${_safeEmail(data['email'])} error=$error',
        );
        debugPrintStack(stackTrace: stackTrace, label: '[Auth] Unexpected');
      }
      rethrow;
    }
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _apiClient.setAuthToken(token);
  }

  void _logAuthAttempt(String action, String email) {
    if (kDebugMode) {
      debugPrint('[Auth] $action attempt email=${_safeEmail(email)}');
    }
  }

  String _safeEmail(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }
}
