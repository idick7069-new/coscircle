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

String participantRoleLabel(String role) {
  return switch (role) {
    'photographer' => '攝影',
    'coser' => 'Coser',
    'manager' => '馬內',
    'self' => '路人',
    _ => '路人',
  };
}
