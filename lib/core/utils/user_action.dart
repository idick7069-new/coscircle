import 'dart:async';
import 'package:flutter/material.dart';
import 'error_message.dart';

Future<bool> runUserAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  unawaited(navigator.push(route));
  Object? failure;
  try {
    await action();
  } catch (error) {
    failure = error;
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
  if (failure != null && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(userFacingError(failure))));
  }
  return failure == null;
}
