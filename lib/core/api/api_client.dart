import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_state.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: _validatedConfiguredBaseUrl());
});

const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
const _allowInsecureApi = bool.fromEnvironment('ALLOW_INSECURE_API');

String _validatedConfiguredBaseUrl() {
  if (!kReleaseMode) return _configuredBaseUrl;
  if (_configuredBaseUrl.isEmpty) {
    throw StateError('Release builds require API_BASE_URL.');
  }
  if (!_allowInsecureApi && !Uri.parse(_configuredBaseUrl).isScheme('https')) {
    throw StateError('Release API_BASE_URL must use HTTPS.');
  }
  return _configuredBaseUrl;
}

class ApiSession {
  ApiSession._(this._client, this._version, this._token);

  final ApiClient _client;
  final int _version;
  final String? _token;
  final CancelToken _cancelToken = CancelToken();

  bool get isActive =>
      !_cancelToken.isCancelled &&
      _version == _client._sessionVersion &&
      _token != null;

  void checkActive() {
    if (!isActive) throw StateError('登入狀態已變更，請重新操作');
  }

  void cancel() {
    _cancelToken.cancel('Session operation ended');
    _client._sessions.remove(this);
  }
}

class ApiClient {
  ApiClient({required String baseUrl, HttpClientAdapter? adapter})
    : baseUrl = baseUrl.isEmpty ? _defaultBaseUrl() : baseUrl,
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.isEmpty ? _defaultBaseUrl() : baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    if (kDebugMode) {
      debugPrint('[ApiClient] baseUrl=${_dio.options.baseUrl}');
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.extra.putIfAbsent('sessionVersion', () => _sessionVersion);
          if (options.extra['sessionVersion'] != _sessionVersion) {
            handler.reject(
              DioException.requestCancelled(
                requestOptions: options,
                reason: 'Session changed',
              ),
            );
            return;
          }
          final session = options.extra['session'] as ApiSession?;
          if (session != null) {
            if (!session.isActive) {
              handler.reject(
                DioException.requestCancelled(
                  requestOptions: options,
                  reason: 'Session operation ended',
                ),
              );
              return;
            }
            options.headers['Authorization'] = 'Bearer ${session._token}';
            handler.next(options);
            return;
          }
          if (_authToken == null && !options.path.startsWith('/auth/')) {
            final version = _sessionVersion;
            final prefs = await SharedPreferences.getInstance();
            if (_sessionVersion == version && !_tokenInitialized) {
              _authToken = prefs.getString('auth_token');
              _tokenInitialized = true;
            }
          }
          if (options.extra['sessionVersion'] != _sessionVersion) {
            handler.reject(
              DioException.requestCancelled(
                requestOptions: options,
                reason: 'Session changed',
              ),
            );
            return;
          }
          final token = _authToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final session =
              response.requestOptions.extra['session'] as ApiSession?;
          if (session != null && !session.isActive) {
            handler.reject(
              DioException.requestCancelled(
                requestOptions: response.requestOptions,
                reason: 'Session operation ended',
              ),
            );
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              !error.requestOptions.path.startsWith('/auth/') &&
              error.requestOptions.extra['sessionVersion'] == _sessionVersion &&
              _authToken != null &&
              error.requestOptions.headers['Authorization'] ==
                  'Bearer $_authToken') {
            // Cancelling this request here would replace its 401 with a cancel error.
            _sessions.remove(error.requestOptions.extra['session']);
            final cleared = persistAuthToken(null);
            final version = _sessionVersion;
            await cleared;
            if (_sessionVersion == version) sessionExpired.value = true;
          }
          handler.next(error);
        },
      ),
    );
  }

  final String baseUrl;
  final Dio _dio;
  String? _authToken;
  bool _tokenInitialized = false;
  int _sessionVersion = 0;
  final ValueNotifier<int> _sessionChanges = ValueNotifier(0);
  final Set<ApiSession> _sessions = {};
  Future<void> _tokenWrites = Future.value();

  int get sessionVersion => _sessionVersion;
  ValueListenable<int> get sessionChanges => _sessionChanges;

  Future<String?> restoreAuthToken() async {
    if (_tokenInitialized) return _authToken;
    final version = _sessionVersion;
    final prefs = await SharedPreferences.getInstance();
    if (_sessionVersion != version || _tokenInitialized) return _authToken;
    final token = prefs.getString('auth_token');
    setAuthToken(token == null || token.isEmpty ? null : token);
    return _authToken;
  }

  Future<void> persistAuthToken(String? token) {
    setAuthToken(token);
    final write = _tokenWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove('auth_token');
      } else {
        await prefs.setString('auth_token', token);
      }
    });
    _tokenWrites = write.catchError((Object _) {});
    return write;
  }

  ApiSession captureSession() {
    final session = ApiSession._(this, _sessionVersion, _authToken);
    session.checkActive();
    _sessions.add(session);
    return session;
  }

  void cancelSessionOperations() {
    _sessionVersion += 1;
    for (final session in _sessions.toList()) {
      session.cancel();
    }
    _sessionChanges.value = _sessionVersion;
  }

  void setAuthToken(String? token) {
    cancelSessionOperations();
    _tokenInitialized = true;
    _authToken = token;
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    ApiSession? session,
  }) {
    session?.checkActive();
    return _dio.get(
      path,
      queryParameters: query,
      options: Options(
        extra: {'session': session, 'sessionVersion': _sessionVersion},
      ),
      cancelToken: session?._cancelToken,
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    ApiSession? session,
  }) {
    session?.checkActive();
    return _dio.post(
      path,
      data: data,
      options: Options(
        receiveTimeout: receiveTimeout,
        extra: {'session': session, 'sessionVersion': _sessionVersion},
      ),
      cancelToken: session?._cancelToken,
    );
  }

  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    ApiSession? session,
  }) {
    session?.checkActive();
    return _dio.put(
      path,
      data: data,
      options: Options(
        extra: {'session': session, 'sessionVersion': _sessionVersion},
      ),
      cancelToken: session?._cancelToken,
    );
  }

  Future<Response<dynamic>> delete(String path, {Map<String, dynamic>? query}) {
    return _dio.delete(
      path,
      queryParameters: query,
      options: Options(extra: {'sessionVersion': _sessionVersion}),
    );
  }

  Future<Response<dynamic>> deleteWithData(
    String path, {
    required Object data,
    ApiSession? session,
  }) {
    session?.checkActive();
    return _dio.delete(
      path,
      data: data,
      options: Options(
        extra: {'session': session, 'sessionVersion': _sessionVersion},
      ),
      cancelToken: session?._cancelToken,
    );
  }

  Future<Response<dynamic>> health() {
    return _dio.get('/health');
  }
}

String _defaultBaseUrl() {
  const devLanBaseUrl = 'https://34.187.168.222/api';
  if (kIsWeb) return devLanBaseUrl;
  if (Platform.isAndroid || Platform.isIOS) return devLanBaseUrl;
  return devLanBaseUrl;
}
