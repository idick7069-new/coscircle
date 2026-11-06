import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/shared/widgets/cos_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('export platform icons from the same approved brand asset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size.square(1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const RepaintBoundary(
          key: ValueKey('brand-export'),
          child: ColoredBox(
            color: Colors.white,
            child: Center(child: CosLogoMark(size: 736)),
          ),
        ),
      ),
    );
    Object? loadError;
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/brand/coscircle-mark.png'),
        tester.element(find.byType(CosLogoMark)),
        onError: (error, stackTrace) => loadError = error,
      );
    });
    expect(loadError, isNull, reason: 'brand asset must decode before export');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!const bool.fromEnvironment('EXPORT_BRAND_ICONS')) return;

    await tester.runAsync(() async {
      const iosFolder = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final manifest =
          jsonDecode(await File('$iosFolder/Contents.json').readAsString())
              as Map<String, dynamic>;
      final targets = <String, int>{
        'build/ui-preview/brand-mark-1024.png': 1024,
        'web/favicon.png': 32,
        'web/icons/Icon-192.png': 192,
        'web/icons/Icon-512.png': 512,
        'web/icons/Icon-maskable-192.png': 192,
        'web/icons/Icon-maskable-512.png': 512,
        for (final entry in {
          'mdpi': 48,
          'hdpi': 72,
          'xhdpi': 96,
          'xxhdpi': 144,
          'xxxhdpi': 192,
        }.entries)
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png':
              entry.value,
        for (final row in manifest['images'] as List<dynamic>)
          '$iosFolder/${row['filename']}':
              (double.parse((row['size'] as String).split('x').first) *
                      double.parse(
                        (row['scale'] as String).replaceAll('x', ''),
                      ))
                  .round(),
      };
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('brand-export')),
      );
      for (final target in targets.entries) {
        final image = await boundary.toImage(pixelRatio: target.value / 1024);
        try {
          expect(image.width, target.value);
          expect(image.height, target.value);
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(
            pixels!.buffer
                .asUint8List()
                .indexed
                .where((entry) => entry.$1 % 4 == 3)
                .every((entry) => entry.$2 == 255),
            isTrue,
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(target.key);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
    });
  });
}
