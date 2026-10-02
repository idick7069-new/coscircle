import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  final normalizedValue = _normalizeDeviceReachableUploadUrl(value);
  if (normalizedValue.startsWith('http://') ||
      normalizedValue.startsWith('https://')) {
    return NetworkImage(normalizedValue);
  }
  return FileImage(File(normalizedValue));
}

String _normalizeDeviceReachableUploadUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || !uri.path.startsWith('/uploads/')) {
    return value;
  }
  final host = uri.host.toLowerCase();
  if (!_isLocalOrPrivateHost(host)) return value;
  return Uri(
    scheme: uri.scheme,
    host: '34.187.168.222',
    path: uri.path,
    query: uri.query.isEmpty ? null : uri.query,
  ).toString();
}

bool _isLocalOrPrivateHost(String host) {
  return host == '127.0.0.1' ||
      host == 'localhost' ||
      host.startsWith('192.168.') ||
      host.startsWith('10.') ||
      host.startsWith('172.16.') ||
      host.startsWith('172.17.') ||
      host.startsWith('172.18.') ||
      host.startsWith('172.19.') ||
      host.startsWith('172.2') ||
      host.startsWith('172.30.') ||
      host.startsWith('172.31.');
}
