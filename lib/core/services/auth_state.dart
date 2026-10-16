import 'package:flutter/foundation.dart';

final sessionExpired = ValueNotifier<bool>(false);

String safeReturnPath(String? value) {
  if (value == null ||
      !value.startsWith('/') ||
      value.startsWith('//') ||
      value.startsWith('/login') ||
      value.startsWith('/onboarding')) {
    return '/';
  }
  return value;
}
