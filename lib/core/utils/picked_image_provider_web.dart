import 'package:flutter/widgets.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  return NetworkImage(value);
}
