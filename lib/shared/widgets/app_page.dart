import 'package:flutter/material.dart';

import 'cos_ui.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: CosUi.surfaceGradient(scheme)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _AppPagePattern(scheme)),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppPagePattern extends CustomPainter {
  const _AppPagePattern(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.028)
      ..strokeWidth = 1;
    const gap = 36.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        linePaint,
      );
    }

    final dashPaint = Paint()
      ..color = scheme.secondary.withValues(alpha: 0.035)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var y = 24.0; y < size.height; y += gap * 1.6) {
      for (var x = 18.0; x < size.width; x += gap * 2.2) {
        canvas.drawLine(Offset(x, y), Offset(x + 8, y), dashPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AppPagePattern oldDelegate) {
    return oldDelegate.scheme != scheme;
  }
}
