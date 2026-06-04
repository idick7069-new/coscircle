import 'package:flutter/material.dart';

Color participantRoleColor(String role) {
  return switch (role) {
    'photographer' => Colors.blue,
    'coser' => Colors.pink,
    'manager' => Colors.amber,
    'self' => Colors.green,
    _ => Colors.green,
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
