import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../services/auth_state.dart';

import '../api/api_client.dart';
import '../config/app_environment.dart';
import '../models/profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(apiClient: ref.watch(apiClientProvider));
});

String? normalizeRegistrationEmail(String value) {
  final email = value.trim().toLowerCase();
  return email.length <= 191 &&
          RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(email)
      ? email
      : null;
}

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

class AuthEmailStatus {
  const AuthEmailStatus({
    this.email,
    required this.verified,
    required this.available,
  });
  final String? email;
  final bool verified;
  final bool available;
  factory AuthEmailStatus.fromJson(Map<String, dynamic> json) =>
      AuthEmailStatus(
        email: json['email'] as String?,
        verified: json['verified'] == true,
        available: json['available'] == true,
      );
}

class AuthRepository {
  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  static const tokenKey = 'auth_token';

  final ApiClient _apiClient;

  Future<String?> restoreToken() async {
    final token = await _apiClient.restoreAuthToken();
    if (token == null || token.isEmpty) return null;
    if (appDemoMode && token == _demoToken) return token;
    final session = _apiClient.captureSession();
    try {
      await _apiClient.get('/me', session: session);
      return token;
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      return null;
    } finally {
      session.cancel();
    }
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final version = _apiClient.sessionVersion;
    if (appDemoMode) {
      final session = _demoSession(isNewUser: false);
      await _saveToken(session.token, version);
      return session;
    }
    final session = await _authenticate(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    await _saveToken(session.token, version);
    return session;
  }

  Future<AuthSession> register({
    required String nickname,
    required String email,
    required String password,
  }) async {
    final version = _apiClient.sessionVersion;
    final normalizedEmail = normalizeRegistrationEmail(email);
    if (normalizedEmail == null) throw ArgumentError('請輸入有效 Email');
    if (appDemoMode) {
      final session = _demoSession(isNewUser: true);
      await _saveToken(session.token, version);
      return session;
    }
    final session = await _authenticate(
      '/auth/register',
      data: {
        'nickname': nickname,
        'email': normalizedEmail,
        'password': password,
      },
    );
    await _saveToken(session.token, version);
    return session;
  }

  Future<AuthSession> socialLogin({
    required SocialLoginProvider provider,
    required String accessToken,
  }) async {
    final version = _apiClient.sessionVersion;
    if (appDemoMode) {
      final session = _demoSession(isNewUser: false);
      await _saveToken(session.token, version);
      return session;
    }
    if (provider == SocialLoginProvider.line &&
        !Uri.parse(_apiClient.baseUrl).isScheme('https')) {
      throw Exception('LINE 登入需要 HTTPS 後端，請先完成正式連線設定');
    }
    final session = await _authenticate(
      '/auth/social',
      data: {'provider': provider.apiValue, 'accessToken': accessToken},
    );
    await _saveToken(session.token, version);
    return session;
  }

  Future<bool> logout({String? pushToken}) async {
    _apiClient.cancelSessionOperations();
    final version = _apiClient.sessionVersion;
    try {
      if (!appDemoMode) {
        await _apiClient.post('/auth/logout', data: {'pushToken': pushToken});
      }
    } catch (_) {
      // Local logout must finish even when the server is unavailable.
    }
    if (_apiClient.sessionVersion != version) return false;
    await _apiClient.persistAuthToken(null);
    return _apiClient.sessionVersion == version + 1;
  }

  Future<List<String>> loginMethods() async {
    final response = await _apiClient.get('/me/auth-identities');
    return (response.data as List)
        .map((row) => (row as Map)['provider'].toString())
        .toList();
  }

  Future<AuthEmailStatus> emailStatus() async {
    final response = await _apiClient.get('/me/email-status');
    return AuthEmailStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> requestEmailVerification() async {
    await _apiClient.post(
      '/me/email-verification',
      receiveTimeout: const Duration(seconds: 20),
    );
  }

  Future<void> forgotPassword(String email) async {
    await _apiClient.post('/auth/forgot-password', data: {'email': email});
  }

  Future<void> verifyEmail(String token) async {
    await _apiClient.post('/auth/verify-email', data: {'token': token});
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await _apiClient.post(
      '/auth/reset-password',
      data: {'token': token, 'password': password},
    );
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    await _apiClient.persistAuthToken(null);
    sessionExpired.value = false;
  }

  Future<void> linkLine({
    required String accessToken,
    required String password,
  }) async {
    if (!Uri.parse(_apiClient.baseUrl).isScheme('https')) {
      throw Exception('綁定 LINE 需要 HTTPS 後端，請先完成正式連線設定');
    }
    await _apiClient.post(
      '/me/auth-identities/line',
      data: {'accessToken': accessToken, 'password': password},
    );
  }

  Future<AuthSession> _authenticate(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final response = await _apiClient.post(path, data: data);
    return AuthSession.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> _saveToken(String token, int expectedVersion) async {
    if (_apiClient.sessionVersion != expectedVersion) {
      throw StateError('登入狀態已變更，請重新操作');
    }
    await _apiClient.persistAuthToken(token);
    if (_apiClient.sessionVersion != expectedVersion + 1) {
      throw StateError('登入狀態已變更，請重新操作');
    }
    sessionExpired.value = false;
  }

  static const _demoToken = 'coscircle-demo-token';

  AuthSession _demoSession({required bool isNewUser}) {
    return AuthSession(
      token: _demoToken,
      isNewUser: isNewUser,
      user: const UserProfile(
        id: 'demo',
        publicCode: 'DEMO001',
        nickname: 'Demo 管理員',
        isAdmin: true,
        bio: 'CosCircle Demo Mode',
        regions: ['北部'],
        travelRegions: ['北部'],
      ),
    );
  }
}
