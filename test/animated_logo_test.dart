import 'dart:ui' as ui;

import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/shared/widgets/cos_animated_logo.dart';
import 'package:coscircle/shared/widgets/cos_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _precacheMark(WidgetTester tester) async {
  Object? loadError;
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/brand/coscircle-mark.png'),
      tester.element(find.byType(CosLogoMark).first),
      onError: (error, stackTrace) => loadError = error,
    );
  });
  expect(
    loadError,
    isNull,
    reason: 'brand asset must decode before pixel checks',
  );
  await tester.pump();
}

Future<List<int>> _pixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectBrandPixels(List<int> pixels, int size) {
  final colors = <String, bool Function(int, int, int)>{
    'teal body': (r, g, b) => g > r + 25 && b > r + 10 && g >= b - 30,
    'coral calendar': (r, g, b) =>
        r > g + 40 && r > b + 25 && g > 35 && b >= g * 0.6,
    'gold fold': (r, g, b) => r > 160 && g > 105 && b < g * 0.7 && r > g + 10,
  };
  for (final color in colors.entries) {
    var count = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] > 180 &&
          color.value(pixels[i], pixels[i + 1], pixels[i + 2])) {
        count++;
      }
    }
    expect(
      count,
      greaterThan(size * size ~/ 2048),
      reason: '${color.key} at ${size}px',
    );
  }
  for (final (x, y) in [
    (0, 0),
    (size - 1, 0),
    (0, size - 1),
    (size - 1, size - 1),
    (size ~/ 2, size ~/ 2),
  ]) {
    final alpha = pixels[(y * size + x) * 4 + 3];
    expect(alpha, 0, reason: 'transparent logo at ($x, $y), ${size}px');
  }
}

void main() {
  Future<void> open(
    WidgetTester tester, {
    bool reduced = false,
    bool accessible = false,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduced,
            accessibleNavigation: accessible,
          ),
          child: const Scaffold(
            body: Center(child: CosAnimatedLogo(key: ValueKey('logo'))),
          ),
        ),
      ),
    );
    await _precacheMark(tester);
  }

  Future<List<int>> renderMark(
    WidgetTester tester, {
    int size = 128,
    bool dark = false,
    double opacity = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Center(
          child: RepaintBoundary(
            key: const ValueKey('mark-pixels'),
            child: CosLogoMark(size: size.toDouble(), markOpacity: opacity),
          ),
        ),
      ),
    );
    await _precacheMark(tester);
    expect(
      tester.getSize(find.byType(CosLogoMark)),
      Size.square(size.toDouble()),
    );
    expect(tester.takeException(), isNull);
    final pixels = await _pixels(
      tester,
      find.byKey(const ValueKey('mark-pixels')),
    );
    expect(pixels.length, size * size * 4);
    return pixels;
  }

  testWidgets('mark defaults to a 42px square at full opacity', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: CosLogoMark())),
    );
    await _precacheMark(tester);
    expect(tester.getSize(find.byType(CosLogoMark)), const Size.square(42));
    expect(tester.widget<CosLogoMark>(find.byType(CosLogoMark)).markOpacity, 1);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final size in [24, 32, 42, 128]) {
      testWidgets('brand colors and alpha at ${size}px, dark=$dark', (
        tester,
      ) async {
        final pixels = await renderMark(tester, size: size, dark: dark);
        _expectBrandPixels(pixels, size);
      });
    }
  }

  testWidgets('opacity fades every part of the mark without changing layout', (
    tester,
  ) async {
    final full = await renderMark(tester);
    final half = await renderMark(tester, opacity: 0.5);
    for (var i = 3; i < full.length; i += 4) {
      expect(
        half[i],
        closeTo(full[i] * 0.5, 2),
        reason: 'alpha at pixel ${i ~/ 4}',
      );
    }
    final hidden = await renderMark(tester, opacity: 0);
    expect([
      for (var i = 3; i < hidden.length; i += 4) hidden[i],
    ], everyElement(0));
  });

  testWidgets('brand fades in without moving its layout', (tester) async {
    await open(tester);
    final before = tester.widget<CosLogoMark>(find.byType(CosLogoMark));
    expect(before.markOpacity, closeTo(0.2, 0.001));
    final size = tester.getSize(find.byKey(const ValueKey('logo')));
    await tester.pump(const Duration(milliseconds: 800));
    final after = tester.widget<CosLogoMark>(find.byType(CosLogoMark));
    expect(after.markOpacity, 1);
    expect(tester.getSize(find.byKey(const ValueKey('logo'))), size);
    expect(size, const Size.square(128));
    await tester.pump(const Duration(seconds: 8));
    expect(tester.widget<CosLogoMark>(find.byType(CosLogoMark)).markOpacity, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets('reduced motion renders the full static brand, dark=$dark', (
      tester,
    ) async {
      await open(tester, reduced: true, dark: dark);
      await tester.pumpAndSettle();
      final logo = tester.widget<CosLogoMark>(find.byType(CosLogoMark));
      expect(logo.markOpacity, 1);
      expect(
        find.descendant(
          of: find.byType(CosAnimatedLogo),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'logo pixels are visible and change between frames, dark=$dark',
      (tester) async {
        await open(tester, dark: dark);
        final boundary = find.descendant(
          of: find.byType(CosAnimatedLogo),
          matching: find.byType(RepaintBoundary),
        );

        final first = await _pixels(tester, boundary);
        expect(
          [
            for (var i = 3; i < first.length; i += 4) first[i],
          ].any((alpha) => alpha > 0),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 800));
        expect(await _pixels(tester, boundary), isNot(equals(first)));
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'accessibility preference disables motion and dynamic preference changes stop the ticker',
    (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 1));
      await open(tester, accessible: true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CosLogoMark>(find.byType(CosLogoMark)).markOpacity,
        1,
      );
      await open(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<CosLogoMark>(find.byType(CosLogoMark)).markOpacity,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
