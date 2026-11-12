import 'dart:ui' as ui;
import 'dart:io';

import 'package:coscircle/core/providers/theme_mode_provider.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/shared/widgets/mimi_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String? assetName(ImageProvider image) {
  if (image is ResizeImage) return assetName(image.imageProvider);
  return image is AssetImage ? image.assetName : null;
}

bool showsAsset(String name) => find
    .byWidgetPredicate(
      (widget) =>
          widget is Image && assetName(widget.image) == 'assets/mimi/cute-v1/$name',
    )
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(() async {
    await (FontLoader('FusionPixel')..addFont(
          rootBundle.load(
            'assets/fonts/fusion-pixel-12px-proportional-zh_hant.ttf',
          ),
        ))
        .load();
  });
  for (final scene in ['reading', 'map']) {
    testWidgets('$scene is a real four-frame looping GIF with distinct poses', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final data = await rootBundle.load('assets/mimi/cute-v1/$scene.gif');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        try {
          expect(codec.frameCount, 4);
          expect(codec.repetitionCount, -1);
          final pictures = <List<int>>[];
          for (var i = 0; i < 4; i++) {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, 64);
            expect(frame.image.height, 64);
            expect(frame.duration.inMilliseconds, greaterThan(0));
            pictures.add(
              (await frame.image.toByteData())!.buffer.asUint8List().toList(),
            );
            frame.image.dispose();
          }
          expect(pictures[1], isNot(equals(pictures[0])));
        } finally {
          codec.dispose();
        }
      });
    });
  }

  testWidgets('all static mascots are native 64px with crisp transparency', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final name in [
        'portrait',
        'avatar-placeholder',
        'reading-still',
        'map-still',
      ]) {
        final data = await rootBundle.load('assets/mimi/cute-v1/$name.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 64, reason: name);
          expect(frame.image.height, 64, reason: name);
          final pixels = (await frame.image.toByteData())!.buffer.asUint8List();
          final alphas = <int>{
            for (var i = 3; i < pixels.length; i += 4) pixels[i],
          };
          expect(alphas, equals({0, 255}), reason: name);
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      }
    });
  });

  testWidgets('all greeting sizes use the half-body portrait', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: MimiMascot(size: 48))),
    );
    expect(showsAsset('portrait.png'), true);
    expect(showsAsset('master.png'), false);
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: MimiMascot(size: 128))),
    );
    expect(showsAsset('master.png'), false);
    expect(showsAsset('portrait.png'), true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mascot stops for reduced motion, hidden tabs and background, then resumes',
    (tester) async {
      Future<void> open({
        bool reduced = false,
        bool visible = true,
        bool accessible = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                disableAnimations: reduced,
                accessibleNavigation: accessible,
              ),
              child: TickerMode(
                enabled: visible,
                child: const MimiMascot(scene: MimiScene.reading),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await open();
      expect(showsAsset('reading.gif'), true);
      await open(reduced: true);
      expect(showsAsset('reading-still.png'), true);
      await open(visible: false);
      expect(showsAsset('reading-still.png'), true);
      await open(accessible: true);
      expect(showsAsset('reading-still.png'), true);
      await open();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(showsAsset('reading-still.png'), true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(showsAsset('reading-still.png'), true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(showsAsset('reading.gif'), true);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing and broken avatars use the local Mimi silhouette without changing size',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: MimiAvatar(radius: 42))),
      );
      expect(tester.getSize(find.byType(MimiAvatar)), const Size.square(84));
      expect(showsAsset('avatar-placeholder.png'), true);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MimiAvatar(
              radius: 42,
              image: MemoryImage(Uint8List.fromList([0, 1, 2])),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(showsAsset('avatar-placeholder.png'), true);
      expect(tester.getSize(find.byType(MimiAvatar)), const Size.square(84));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading stays readable and scrollable in a short screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: const Scaffold(
              body: MimiLoading(scene: MimiScene.map, label: '希希正在查看場次地圖…'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('希希正在查看場次地圖…'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'pixel theme starts dark once and preserves subsequent user choices',
    () async {
      SharedPreferences.setMockInitialValues({
        'coscircle_theme_mode': 'morandi_light',
      });
      final container = ProviderContainer();
      expect(container.read(appThemeModeProvider), CosCircleThemeMode.neonDark);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appThemeModeProvider), CosCircleThemeMode.neonDark);
      await container
          .read(appThemeModeProvider.notifier)
          .setMode(CosCircleThemeMode.morandiLight);
      container.dispose();
      final reopened = ProviderContainer();
      reopened.read(appThemeModeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        reopened.read(appThemeModeProvider),
        CosCircleThemeMode.morandiLight,
      );
      reopened.dispose();
    },
  );

  test(
    'theme selection during initial restoration wins over saved state',
    () async {
      SharedPreferences.setMockInitialValues({
        'coscircle_pixel_theme_mode_v1': 'neon_dark',
      });
      final container = ProviderContainer();
      container.read(appThemeModeProvider);
      await container
          .read(appThemeModeProvider.notifier)
          .setMode(CosCircleThemeMode.morandiLight);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(appThemeModeProvider),
        CosCircleThemeMode.morandiLight,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'coscircle_pixel_theme_mode_v1',
        ),
        'morandi_light',
      );
      container.dispose();
    },
  );

  if (const bool.fromEnvironment('QA_SCREENSHOTS')) {
    for (final (scene, label) in [
      (MimiScene.reading, '正在確認登入狀態'),
      (MimiScene.reading, '希希正在整理活動…'),
      (MimiScene.map, '希希正在查看場次地圖…'),
    ]) {
      testWidgets('render ${scene.name} $label loading preview', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: RepaintBoundary(
                key: const ValueKey('mimi-preview'),
                child: Scaffold(
                  body: Center(
                    child: MimiLoading(scene: scene, label: label),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await precacheImage(
            AssetImage('assets/mimi/cute-v1/${scene.name}-still.png'),
            tester.element(find.byType(MimiLoading)),
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('mimi-preview')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/ui-preview/${scene.name}-loading-dark.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      });
    }
  }
}
