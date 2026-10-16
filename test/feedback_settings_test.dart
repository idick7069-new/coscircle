import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <MethodCall>[];
  var canLaunch = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    launches.clear();
    canLaunch = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          launches.add(call);
          return canLaunch;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> open(WidgetTester tester, String url) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            InMemoryProfileRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SettingsPage(feedbackFormUrl: url)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('feedback is hidden until a form is configured', (tester) async {
    await open(tester, '');
    expect(find.text('意見回饋'), findsNothing);
  });

  for (final url in [
    'https://forms.gle/QAForm',
    'https://docs.google.com/forms/d/e/QAForm/viewform?usp=sf_link',
  ]) {
    testWidgets('opens configured Google form externally: $url', (
      tester,
    ) async {
      await open(tester, url);
      await tester.scrollUntilVisible(find.text('意見回饋'), 200);
      await tester.tap(find.text('意見回饋'));
      await tester.pumpAndSettle();
      expect(launches, hasLength(1));
      expect(launches.single.arguments['url'], url);
      expect(launches.single.arguments['useWebView'], false);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('edit links are rejected without launching', (tester) async {
    await open(tester, 'https://docs.google.com/forms/d/QAForm/edit');
    await tester.scrollUntilVisible(find.text('意見回饋'), 200);
    await tester.tap(find.text('意見回饋'));
    await tester.pumpAndSettle();
    expect(launches, isEmpty);
    expect(find.text('意見回饋表單連結尚未設定完成'), findsOneWidget);
  });

  testWidgets('launch failure is visible', (tester) async {
    canLaunch = false;
    await open(tester, 'https://forms.gle/QAForm');
    await tester.scrollUntilVisible(find.text('意見回饋'), 200);
    await tester.tap(find.text('意見回饋'));
    await tester.pumpAndSettle();
    expect(find.text('無法開啟意見回饋表單，請稍後再試'), findsOneWidget);
  });
}
