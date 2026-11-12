import 'package:flutter/material.dart';

class PixelIcon extends StatelessWidget {
  const PixelIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;

  static const _person = [
    '............',
    '....####....',
    '...######...',
    '...######...',
    '....####....',
    '............',
    '..########..',
    '.##########.',
    '.##########.',
    '.##......##.',
    '............',
    '............',
  ];
  static const _calendar = [
    '..#......#..',
    '..#......#..',
    '.##########.',
    '.#........#.',
    '.##########.',
    '.#..#..#..#.',
    '.#........#.',
    '.#..#..#..#.',
    '.#........#.',
    '.##########.',
    '............',
    '............',
  ];
  static const _pin = [
    '....####....',
    '...#....#...',
    '..#..##..#..',
    '..#.####.#..',
    '..#.####.#..',
    '..#..##..#..',
    '...#....#...',
    '...#....#...',
    '....#..#....',
    '.....##.....',
    '.....##.....',
    '............',
  ];
  static const _people = [
    '..##....##..',
    '.####..####.',
    '.####..####.',
    '..##....##..',
    '............',
    '.####..####.',
    '######.#####',
    '##..##.##.##',
    '##..##.##.##',
    '............',
    '............',
    '............',
  ];
  static const _gear = [
    '....####....',
    '.##.####.##.',
    '.##########.',
    '..########..',
    '####....####',
    '####.##.####',
    '####.##.####',
    '####....####',
    '..########..',
    '.##########.',
    '.##.####.##.',
    '....####....',
  ];
  static const _heart = [
    '............',
    '..###..###..',
    '.##########.',
    '.##########.',
    '.##########.',
    '..########..',
    '...######...',
    '....####....',
    '.....##.....',
    '............',
    '............',
    '............',
  ];
  static const _star = [
    '.....##.....',
    '.....##.....',
    '....####....',
    '.##########.',
    '..########..',
    '...######...',
    '..########..',
    '..###..###..',
    '..##....##..',
    '............',
    '............',
    '............',
  ];
  static final _patterns = <int, List<String>>{
    for (final data in [
      Icons.badge,
      Icons.badge_outlined,
      Icons.person,
      Icons.person_outline,
      Icons.face,
    ])
      data.codePoint: _person,
    for (final data in [
      Icons.event,
      Icons.event_outlined,
      Icons.event_note,
      Icons.event_note_outlined,
      Icons.calendar_month,
      Icons.calendar_month_outlined,
    ])
      data.codePoint: _calendar,
    for (final data in [
      Icons.location_on,
      Icons.location_on_outlined,
      Icons.map,
      Icons.map_outlined,
      Icons.near_me,
      Icons.near_me_outlined,
    ])
      data.codePoint: _pin,
    for (final data in [
      Icons.people,
      Icons.people_outline,
      Icons.groups,
      Icons.groups_outlined,
      Icons.diversity_3,
      Icons.diversity_3_outlined,
    ])
      data.codePoint: _people,
    for (final data in [Icons.settings, Icons.settings_outlined, Icons.tune])
      data.codePoint: _gear,
    for (final data in [Icons.favorite, Icons.favorite_border])
      data.codePoint: _heart,
    for (final data in [Icons.star, Icons.star_outline, Icons.auto_awesome])
      data.codePoint: _star,
  };

  @override
  Widget build(BuildContext context) {
    final pattern = _patterns[icon.codePoint];
    if (pattern == null) return Icon(icon, size: size, color: color);
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: size ?? theme.size ?? 24,
      child: CustomPaint(
        painter: _PixelIconPainter(
          pattern,
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _PixelIconPainter extends CustomPainter {
  const _PixelIconPainter(this.pattern, this.color);
  final List<String> pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.shortestSide / 12;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var y = 0; y < pattern.length; y++) {
      for (var x = 0; x < pattern[y].length; x++) {
        if (pattern[y][x] == '#') {
          canvas.drawRect(Rect.fromLTWH(x * step, y * step, step, step), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelIconPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color;
}
