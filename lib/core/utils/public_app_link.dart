import 'package:flutter/foundation.dart';

String publicAppLink(String path) {
  const configured = String.fromEnvironment('PUBLIC_APP_URL');
  const api = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://34.187.168.222/api',
  );
  final origin = kIsWeb && Uri.base.hasAuthority
      ? Uri.base.origin
      : Uri.parse(api).origin;
  final base = configured.isEmpty
      ? '$origin/app'
      : configured.replaceAll(RegExp(r'/+$'), '');
  return '$base/#$path';
}
