import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(value);
  }
  return FileImage(File(value));
}
