import 'dart:ui' as ui;

import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/shared/widgets/cos_animated_logo.dart';
import 'package:coscircle/shared/widgets/cos_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

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
  }

  testWidgets(
    'orbit rotates independently while central mark fades and layout remains stable',
    (tester) async {
      await open(tester);
      final before = tester.widget<CosLogoMark>(find.byType(CosLogoMark));
      expect(before.markOpacity, closeTo(0.2, 0.001));
      final size = tester.getSize(find.byKey(const ValueKey('logo')));
      await tester.pump(const Duration(milliseconds: 800));
      final after = tester.widget<CosLogoMark>(find.byType(CosLogoMark));
      expect(after.orbitRotation, greaterThan(before.orbitRotation));
      expect(after.markOpacity, 1);
      expect(tester.getSize(find.byKey(const ValueKey('logo'))), size);
      expect(size, const Size.square(128));
      await tester.pump(const Duration(seconds: 8));
      expect(
        tester.widget<CosLogoMark>(find.byType(CosLogoMark)).markOpacity,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets('reduced motion renders the full static brand, dark=$dark', (
      tester,
    ) async {
      await open(tester, reduced: true, dark: dark);
      await tester.pumpAndSettle();
      final logo = tester.widget<CosLogoMark>(find.byType(CosLogoMark));
      expect(logo.markOpacity, 1);
      expect(logo.orbitRotation, 0);
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
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.descendant(
            of: find.byType(CosAnimatedLogo),
            matching: find.byType(RepaintBoundary),
          ),
        );
        Future<List<int>> pixels() async {
          return (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              return data!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }))!;
        }

        final first = await pixels();
        expect(
          [
            for (var i = 3; i < first.length; i += 4) first[i],
          ].any((alpha) => alpha > 0),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 800));
        expect(await pixels(), isNot(equals(first)));
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
        tester.widget<CosLogoMark>(find.byType(CosLogoMark)).orbitRotation,
        0,
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
