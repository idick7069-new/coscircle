import 'secure_media_image.dart';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'picked_image_url.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  final canonical = pickedImageUrl(value);
  if (isProtectedMedia(canonical)) return SecureMediaImage(canonical);
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(pickedImageUrl(value));
  }
  return FileImage(File(value));
}
