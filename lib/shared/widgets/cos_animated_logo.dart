import 'package:flutter/material.dart';

import 'mimi_mascot.dart';

class CosAnimatedLogo extends StatelessWidget {
  const CosAnimatedLogo({super.key, this.size = 128});

  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        !TickerMode.of(context);
    final mascot = SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: MimiMascot(scene: MimiScene.reading, size: size, animate: false),
      ),
    );
    return Semantics(
      label: 'CosCircle 希希',
      image: true,
      child: ExcludeSemantics(
        child: reduceMotion
            ? mascot
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.2, end: 1),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: mascot,
              ),
      ),
    );
  }
}
