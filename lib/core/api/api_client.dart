import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: const String.fromEnvironment('API_BASE_URL'));
});

class ApiClient {
  ApiClient({required String baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.isEmpty ? _defaultBaseUrl() : baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) {
    return _dio.get(path, queryParameters: query);
  }

  Future<Response<dynamic>> post(String path, {Object? data}) {
    return _dio.post(path, data: data);
  }

  Future<Response<dynamic>> put(String path, {Object? data}) {
    return _dio.put(path, data: data);
  }

  Future<Response<dynamic>> delete(String path) {
    return _dio.delete(path);
  }
}

String _defaultBaseUrl() {
  if (kIsWeb) return 'http://127.0.0.1:8080/api';
  if (Platform.isAndroid) return 'http://10.0.2.2:8080/api';
  return 'http://127.0.0.1:8080/api';
}
