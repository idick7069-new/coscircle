import 'secure_media_image.dart';
import 'package:flutter/widgets.dart';

import 'picked_image_url.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  final canonical = pickedImageUrl(value);
  if (isProtectedMedia(canonical)) return SecureMediaImage(canonical);
  return NetworkImage(
    pickedImageUrl(value),
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
  );
}
