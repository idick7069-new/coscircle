import 'package:flutter/widgets.dart';

import 'picked_image_url.dart';

ImageProvider? pickedImageProvider(String value) {
  if (value.isEmpty) return null;
  return NetworkImage(
    pickedImageUrl(value),
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
  );
}
