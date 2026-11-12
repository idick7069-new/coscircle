import 'dart:io';

import 'package:flutter/widgets.dart';

import 'picked_image_url.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(pickedImageUrl(value));
  }
  return FileImage(File(value));
}
