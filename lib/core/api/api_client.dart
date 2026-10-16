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

class ApiClient {
  ApiClient({required String baseUrl})
    : baseUrl = baseUrl.isEmpty ? _defaultBaseUrl() : baseUrl,
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.isEmpty ? _defaultBaseUrl() : baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ) {
    if (kDebugMode) {
      debugPrint('[ApiClient] baseUrl=${_dio.options.baseUrl}');
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_authToken == null && !options.path.startsWith('/auth/')) {
            _authToken = (await SharedPreferences.getInstance()).getString(
              'auth_token',
            );
          }
          final token = _authToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              !error.requestOptions.path.startsWith('/auth/') &&
              _authToken != null &&
              error.requestOptions.headers['Authorization'] ==
                  'Bearer $_authToken') {
            _authToken = null;
            await (await SharedPreferences.getInstance()).remove('auth_token');
            sessionExpired.value = true;
          }
          handler.next(error);
        },
      ),
    );
  }

  final String baseUrl;
  final Dio _dio;
  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) {
    return _dio.get(path, queryParameters: query);
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Duration? receiveTimeout,
  }) {
    return _dio.post(
      path,
      data: data,
      options: receiveTimeout == null
          ? null
          : Options(receiveTimeout: receiveTimeout),
    );
  }

  Future<Response<dynamic>> put(String path, {Object? data}) {
    return _dio.put(path, data: data);
  }

  Future<Response<dynamic>> delete(String path, {Map<String, dynamic>? query}) {
    return _dio.delete(path, queryParameters: query);
  }

  Future<Response<dynamic>> deleteWithData(
    String path, {
    required Object data,
  }) {
    return _dio.delete(path, data: data);
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
