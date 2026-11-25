import 'package:dio/dio.dart';
import 'package:dio/browser.dart';

void configureCookieTransport(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
  dio.options.headers['X-CosCircle-Client'] = 'web';
}
