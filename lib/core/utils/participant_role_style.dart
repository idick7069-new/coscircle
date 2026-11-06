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
    'photographer' => AppTheme.cyan,
    'coser' => AppTheme.coral,
    'manager' => const Color(0xff846000),
    'self' => const Color(0xff38694d),
    _ => const Color(0xff38694d),
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

IconData participantRoleIcon(String role) {
  return switch (role) {
    'photographer' => Icons.photo_camera_outlined,
    'coser' => Icons.theater_comedy_outlined,
    'manager' => Icons.support_agent_outlined,
    'self' => Icons.explore_outlined,
    _ => Icons.badge_outlined,
  };
}
