import 'dart:math' as math;

import 'package:flutter/material.dart';

class ProfileReadinessCelebration extends StatefulWidget {
  const ProfileReadinessCelebration({super.key});

  @override
  State<ProfileReadinessCelebration> createState() =>
      _ProfileReadinessCelebrationState();
}

class _ProfileReadinessCelebrationState
    extends State<ProfileReadinessCelebration>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  final _badgeScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.75,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 20,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
  ]);
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.value = 1;
    } else if (_reduceMotion == null) {
      _controller.forward();
    }
    _reduceMotion = reduceMotion;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('profile-readiness-celebration'),
      scrollable: true,
      icon: ExcludeSemantics(
        child: SizedBox(
          height: 144,
          width: 260,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _reduceMotion == true
                  ? null
                  : _CelebrationConfetti(
                      progress: _controller.value,
                      colors: [
                        scheme.primary,
                        scheme.secondary,
                        scheme.tertiary,
                      ],
                    ),
              child: Center(
                child: Transform.scale(
                  key: const ValueKey('readiness-celebration-badge'),
                  scale: _badgeScale.transform(_controller.value),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.secondaryContainer,
                      border: Border.all(color: scheme.secondary, width: 3),
                    ),
                    child: Icon(
                      Icons.done_rounded,
                      size: 52,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      title: const Text('恭喜！名片準備好了', textAlign: TextAlign.center),
      content: const Text('9/9 全部完成，準備好讓同好認識你了！', textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.celebration_outlined),
          label: const Text('太好了'),
        ),
      ],
    );
  }
}

class _CelebrationConfetti extends CustomPainter {
  const _CelebrationConfetti({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final spread = Curves.easeOutCubic.transform(progress);
    final paint = Paint();
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi * 2 / 24;
      final distance = 46 + (22 + (i % 4) * 12) * spread;
      final center = Offset(
        size.width / 2 + math.cos(angle) * distance,
        size.height / 2 +
            math.sin(angle) * distance * 0.55 +
            12 * progress * progress,
      );
      paint.color = colors[i % colors.length].withValues(
        alpha: (1 - progress) * 0.95,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + progress * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -5, 6, 10),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationConfetti oldDelegate) =>
      progress != oldDelegate.progress || colors != oldDelegate.colors;
}
