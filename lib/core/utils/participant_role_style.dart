import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Color participantRoleColor(String role) {
  return switch (role) {
    'photographer' => AppTheme.techBlue,
    'coser' => AppTheme.neonPink,
    'manager' => AppTheme.spotlightYellow,
    'self' => AppTheme.acidGreen,
    _ => AppTheme.acidGreen,
  };
}

Color participantRoleColorForScheme(String role, ColorScheme scheme) {
  if (scheme.brightness == Brightness.dark) {
    return participantRoleColor(role);
  }
  return switch (role) {
    'photographer' => const Color(0xff6f8fa6),
    'coser' => const Color(0xffb58f8f),
    'manager' => const Color(0xffb7a777),
    'self' => const Color(0xff839a7c),
    _ => const Color(0xff839a7c),
  };
}

String participantRoleLabel(String role) {
  return switch (role) {
    'photographer' => '攝影',
    'coser' => 'Coser',
    'manager' => '馬內',
    'self' => '路人',
    _ => '路人',
  };
}
