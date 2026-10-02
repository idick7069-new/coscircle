import 'dart:math' as math;

import 'package:flutter/material.dart';

class CosUi {
  static const radiusSm = 12.0;
  static const radiusMd = 18.0;
  static const radiusLg = 24.0;
  static const radiusXl = 32.0;

  static BoxShadow softShadow(Color color) {
    return BoxShadow(
      color: color.withValues(alpha: 0.12),
      blurRadius: 26,
      offset: const Offset(0, 14),
    );
  }

  static LinearGradient surfaceGradient(ColorScheme scheme) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surface,
      ],
    );
  }
}

class CosLogoMark extends StatelessWidget {
  const CosLogoMark({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _CosLogoMarkPainter(scheme),
    );
  }
}

class _CosLogoMarkPainter extends CustomPainter {
  const _CosLogoMarkPainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width * 0.27;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.surfaceContainerHighest, scheme.surfaceContainerLow],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      background,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..color = scheme.outlineVariant.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(size.width * 0.015),
        Radius.circular(radius),
      ),
      border,
    );

    final center = rect.center;
    final stroke = size.width * 0.105;
    final leftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = scheme.primary;
    final rightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = scheme.secondary;
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.025
      ..color = scheme.tertiary.withValues(alpha: 0.75);

    final markRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.58,
      height: size.height * 0.58,
    );
    canvas.drawArc(
      markRect.shift(Offset(-size.width * 0.08, 0)),
      math.pi * 0.25,
      math.pi * 1.35,
      false,
      leftPaint,
    );
    canvas.drawArc(
      markRect.shift(Offset(size.width * 0.08, 0)),
      math.pi * 1.05,
      math.pi * 1.35,
      false,
      rightPaint,
    );
    canvas.drawOval(markRect.inflate(size.width * 0.07), orbitPaint);

    final sparkle = Paint()..color = scheme.tertiary;
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.28),
      size.width * 0.045,
      sparkle,
    );
  }

  @override
  bool shouldRepaint(covariant _CosLogoMarkPainter oldDelegate) {
    return oldDelegate.scheme != scheme;
  }
}

class CosPageHeader extends StatelessWidget {
  const CosPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading ?? const CosLogoMark(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 10),
            Wrap(spacing: 6, children: actions),
          ],
        ],
      ),
    );
  }
}

class CosCard extends StatelessWidget {
  const CosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(CosUi.radiusLg);
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(
          color: borderColor.withValues(alpha: selected ? 0.95 : 0.72),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: child,
    );

    if (onTap == null) return content;
    return _CosCardTapSurface(radius: radius, onTap: onTap!, child: content);
  }
}

class _CosCardTapSurface extends StatefulWidget {
  const _CosCardTapSurface({
    required this.radius,
    required this.onTap,
    required this.child,
  });

  final BorderRadius radius;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_CosCardTapSurface> createState() => _CosCardTapSurfaceState();
}

class _CosCardTapSurfaceState extends State<_CosCardTapSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      scale: _pressed ? 0.985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: widget.radius,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: widget.child,
        ),
      ),
    );
  }
}

class CosReveal extends StatefulWidget {
  const CosReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<CosReveal> createState() => _CosRevealState();
}

class _CosRevealState extends State<CosReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curve);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class CosScannerOverlay extends StatefulWidget {
  const CosScannerOverlay({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accentColor,
    this.statusIcon,
    this.statusLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? accentColor;
  final IconData? statusIcon;
  final String? statusLabel;

  @override
  State<CosScannerOverlay> createState() => _CosScannerOverlayState();
}

class _CosScannerOverlayState extends State<CosScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = widget.accentColor ?? scheme.secondary;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final scanSize = (width - 72).clamp(220.0, 340.0);
          final top = (height * 0.18).clamp(84.0, 154.0);
          final bottomCardWidth = (width - 48).clamp(0.0, 440.0);
          final statusLabel = widget.statusLabel;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.86,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.56),
                      ],
                      stops: const [0, 0.56, 1],
                    ),
                  ),
                ),
              ),
              if (statusLabel != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: 18,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest.withValues(
                          alpha: 0.88,
                        ),
                        borderRadius: BorderRadius.circular(CosUi.radiusLg),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.28),
                        ),
                        boxShadow: [CosUi.softShadow(Colors.black)],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.statusIcon ?? Icons.center_focus_strong,
                              color: accent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: (width - scanSize) / 2,
                top: top,
                width: scanSize,
                height: scanSize,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final glow = reduceMotion
                        ? 0.65
                        : 0.44 + _pulse.value * 0.28;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(CosUi.radiusXl),
                        border: Border.all(
                          color: accent.withValues(alpha: glow),
                          width: 2.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: glow * 0.28),
                            blurRadius: 26,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Stack(
                    children: [
                      for (final corner in _ScannerCornerAlignment.values)
                        _ScannerCorner(
                          alignment: corner.alignment,
                          color: accent,
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (width - bottomCardWidth) / 2,
                width: bottomCardWidth,
                bottom: 24,
                child: CosCard(
                  child: Row(
                    children: [
                      CosIconBubble(icon: widget.icon, color: accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CosBadge(
                              label: 'CosCircle 掃描',
                              icon: Icons.center_focus_strong_outlined,
                              color: accent,
                              highlighted: true,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _ScannerCornerAlignment {
  topLeft(Alignment.topLeft),
  topRight(Alignment.topRight),
  bottomLeft(Alignment.bottomLeft),
  bottomRight(Alignment.bottomRight);

  const _ScannerCornerAlignment(this.alignment);

  final Alignment alignment;
}

class _ScannerCorner extends StatelessWidget {
  const _ScannerCorner({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.crop_free_rounded,
          color: color.withValues(alpha: 0.9),
          size: 24,
        ),
      ),
    );
  }
}

class CosGradientPanel extends StatelessWidget {
  const CosGradientPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.icon,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CosUi.radiusXl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.92),
            scheme.secondaryContainer.withValues(alpha: 0.78),
            scheme.tertiaryContainer.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.46),
        ),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CosUi.radiusXl),
        child: Stack(
          children: [
            if (icon != null)
              Positioned(
                right: -22,
                top: -22,
                child: Icon(
                  icon,
                  size: 128,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.07),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class CosSectionHeader extends StatelessWidget {
  const CosSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          CosIconBubble(icon: icon!, size: 36),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class CosInfoTile extends StatelessWidget {
  const CosInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosIconBubble(icon: icon, color: accent, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CosMetricTile extends StatelessWidget {
  const CosMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CosBadge extends StatelessWidget {
  const CosBadge({
    super.key,
    required this.label,
    this.icon,
    this.highlighted = false,
    this.color,
  });

  final String label;
  final IconData? icon;
  final bool highlighted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? (highlighted ? scheme.secondary : scheme.primary);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: highlighted ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: highlighted ? accent : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CosChoicePill extends StatefulWidget {
  const CosChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;
  final bool enabled;

  @override
  State<CosChoicePill> createState() => _CosChoicePillState();
}

class _CosChoicePillState extends State<CosChoicePill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = widget.color ?? scheme.primary;
    final enabled = widget.enabled;
    return AnimatedScale(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      scale: _pressed ? 0.97 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? widget.onTap : null,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? accent.withValues(alpha: 0.14)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: widget.selected
                    ? accent.withValues(alpha: 0.5)
                    : scheme.outlineVariant.withValues(alpha: 0.58),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.selected
                      ? Icons.check_circle_outline
                      : (widget.icon ?? Icons.radio_button_unchecked),
                  size: 16,
                  color: enabled
                      ? (widget.selected ? accent : scheme.onSurfaceVariant)
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: enabled
                        ? (widget.selected ? accent : scheme.onSurface)
                        : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CosLoadingPulse extends StatefulWidget {
  const CosLoadingPulse({
    super.key,
    this.color,
    this.size = 22,
    this.dotCount = 3,
  });

  final Color? color;
  final double size;
  final int dotCount;

  @override
  State<CosLoadingPulse> createState() => _CosLoadingPulseState();
}

class _CosLoadingPulseState extends State<CosLoadingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = widget.color ?? scheme.primary;
    final count = widget.dotCount.clamp(2, 5);
    final dotSize = widget.size * 0.22;

    if (reduceMotion) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: SizedBox.square(dimension: dotSize),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < count; index += 1) ...[
                Transform.translate(
                  offset: Offset(
                    0,
                    -math.sin((_controller.value * math.pi * 2) + index) *
                        widget.size *
                        0.08,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(
                        alpha: 0.36 + (index + 1) / count * 0.46,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: SizedBox.square(dimension: dotSize),
                  ),
                ),
                if (index != count - 1) SizedBox(width: dotSize * 0.62),
              ],
            ],
          );
        },
      ),
    );
  }
}

class CosSafetyConfirmDialog extends StatelessWidget {
  const CosSafetyConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.icon = Icons.shield_outlined,
    this.cancelLabel = '返回',
    this.destructive = false,
  });

  final String title;
  final String message;
  final String actionLabel;
  final IconData icon;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = destructive ? scheme.error : scheme.primary;
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      child: CosGradientPanel(
        icon: icon,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CosIconBubble(icon: icon, color: accent, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          )
                        : null,
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icon(icon),
                    label: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CosIconBubble extends StatelessWidget {
  const CosIconBubble({
    super.key,
    required this.icon,
    this.color,
    this.size = 42,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Icon(icon, color: accent, size: size * 0.52),
    );
  }
}

class CosAvatarStack extends StatelessWidget {
  const CosAvatarStack({
    super.key,
    required this.avatars,
    this.names = const [],
    this.maxVisible = 8,
    this.radius = 13,
  });

  final List<ImageProvider?> avatars;
  final List<String> names;
  final int maxVisible;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final visible = avatars.take(maxVisible).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final step = radius * 1.55;
    return SizedBox(
      height: radius * 2 + 4,
      width: radius * 2 + math.max(0, visible.length - 1) * step + 4,
      child: Stack(
        children: [
          for (final entry in visible.indexed)
            Positioned(
              left: entry.$1 * step,
              child: Tooltip(
                message: entry.$1 < names.length ? names[entry.$1] : '',
                child: CircleAvatar(
                  radius: radius + 2,
                  backgroundColor: scheme.surfaceContainerLowest,
                  child: CircleAvatar(
                    radius: radius,
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage: entry.$2,
                    child: entry.$2 == null
                        ? Text(
                            entry.$1 < names.length &&
                                    names[entry.$1].isNotEmpty
                                ? names[entry.$1].characters.first
                                : '?',
                            style: Theme.of(context).textTheme.labelSmall,
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
