import 'package:flutter/foundation.dart';

const appDemoMode = bool.fromEnvironment('DEMO_MODE');
const accountSafetyEnabled = bool.fromEnvironment(
  'ENABLE_ACCOUNT_SAFETY',
  defaultValue: !kReleaseMode,
);
