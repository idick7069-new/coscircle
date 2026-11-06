import 'package:flutter/material.dart';

import 'cos_ui.dart';

/// Decorative brand artwork, kept separate from user media and map content.
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
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(CosUi.radiusLg),
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Image.asset(
            kind == CosIllustrationKind.people
                ? 'assets/illustrations/meet-your-circle.png'
                : 'assets/illustrations/next-event.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    ),
  );
}
