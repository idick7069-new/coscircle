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
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: radius, onTap: onTap, child: content),
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlighted ? accent : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
