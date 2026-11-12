import 'package:flutter/material.dart';

import 'mimi_mascot.dart';

enum CosIllustrationKind { people, event }

class CosIllustration extends StatelessWidget {
  const CosIllustration({
    super.key,
    this.height = 128,
    this.kind = CosIllustrationKind.people,
  });

  final double height;
  final CosIllustrationKind kind;

  @override
  Widget build(BuildContext context) {
    final illustrationHeight = height.clamp(0.0, 160.0).toDouble();
    return ExcludeSemantics(
      child: SizedBox(
        height: illustrationHeight,
        width: double.infinity,
        child: Center(
          child: MimiMascot(
            scene: kind == CosIllustrationKind.people
                ? MimiScene.hello
                : MimiScene.reading,
            size: illustrationHeight,
            animate: false,
          ),
        ),
      ),
    );
  }
}
