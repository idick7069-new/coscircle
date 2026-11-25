import 'dart:io';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/features/events/presentation/event_booking_share_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  testWidgets(
    'export real booking share image for official site',
    (tester) async {
      await initializeDateFormatting('zh_TW');
      await (FontLoader('FusionPixel')..addFont(
            rootBundle.load(
              'assets/fonts/fusion-pixel-12px-proportional-zh_hant.ttf',
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = Directory.systemTemp.createTempSync('official-booking-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const share = MethodChannel('dev.fluttercommunity.plus/share');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      Uint8List? exported;
      messenger.setMockMethodCallHandler(paths, (_) async => temp.path);
      messenger.setMockMethodCallHandler(share, (call) async {
        exported = File(
          ((call.arguments as Map)['paths'] as List).single as String,
        ).readAsBytesSync();
        return 'official-example';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(share, null);
      });
      final event = CosEvent(
        id: 'official-example',
        name: '週末同好交流場',
        category: '同人活動',
        startDate: DateTime(2026, 12, 12),
        endDate: DateTime(2026, 12, 13),
        venue: '同好廣場',
        detailedAddress: '',
        fee: '',
        organizer: '',
        description: '官網範例資料',
      );
      final portrait = File('assets/mimi/cute-v1/portrait.png').absolute.path;
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SizedBox()),
      );
      await tester.runAsync(() async {
        await precacheImage(
          FileImage(File(portrait)),
          tester.element(find.byType(SizedBox).first),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('zh', 'TW'),
          supportedLocales: const [Locale('zh', 'TW')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: EventBookingSharePage(
            event: event,
            bookings: [
              EventParticipant(
                userId: 'example',
                nickname: '希希 CC',
                role: 'coser',
                dayIndex: 1,
                characterName: '希希・馬內',
                outfitImageUrl: portrait,
                message: '歡迎來找我認親！一起聊聊喜歡的作品。',
                isMe: true,
              ),
              EventParticipant(
                userId: 'example',
                nickname: '希希 CC',
                role: 'coser',
                dayIndex: 2,
                characterName: '希希・日常',
                outfitImageUrl: portrait,
                isMe: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享圖片'));
      await tester.pump();
      for (var i = 0; exported == null && i < 150; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(exported, isNotNull);
      await tester.runAsync(() async {
        final out = File('web/official/assets/booking-example-v1/share.png');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(exported!);
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: !const bool.fromEnvironment('EXPORT_OFFICIAL_BOOKING'),
  );
}
