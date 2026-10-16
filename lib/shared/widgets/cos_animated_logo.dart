import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cos_ui.dart';

class CosAnimatedLogo extends StatefulWidget {
  const CosAnimatedLogo({super.key, this.size = 128});

  final double size;

  @override
  State<CosAnimatedLogo> createState() => _CosAnimatedLogoState();
}

class _CosAnimatedLogoState extends State<CosAnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionEnabled = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _controller.addListener(() {
      if ((_controller.lastElapsedDuration?.inMilliseconds ?? 0) >= 400) {
        _revealed = true;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionEnabled =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (_motionEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _revealed = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markSize = widget.size * 0.88;
    return Semantics(
      label: 'CosCircle',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: Center(
              child: _motionEnabled
                  ? AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final elapsed =
                            (_controller.lastElapsedDuration?.inMilliseconds ??
                                0) /
                            400;
                        final opacity = _revealed
                            ? 1.0
                            : 0.2 +
                                  0.8 *
                                      Curves.easeOutCubic.transform(
                                        elapsed.clamp(0.0, 1.0),
                                      );
                        final scale =
                            1 +
                            0.012 * math.sin(_controller.value * math.pi * 4);
                        return Transform.scale(
                          scale: scale,
                          child: CosLogoMark(
                            size: markSize,
                            orbitRotation: _controller.value * math.pi * 2,
                            markOpacity: opacity,
                          ),
                        );
                      },
                    )
                  : CosLogoMark(size: markSize),
            ),
          ),
        ),
      ),
    );
  }
}
