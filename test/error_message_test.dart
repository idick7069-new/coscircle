import 'package:coscircle/core/utils/error_message.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('401 invalid credentials uses backend error code message', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      response: Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/auth/login'),
        statusCode: 401,
        data: {'error': 'invalid_credentials'},
      ),
    );

    expect(userFacingError(error), 'Email 或密碼不正確');
  });

  test('401 without backend error remains expired login message', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/me'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/me'),
        statusCode: 401,
      ),
    );

    expect(userFacingError(error), '登入狀態已失效，請重新登入');
  });
}
