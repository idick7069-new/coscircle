import 'package:coscircle/app/cos_circle_app.dart';
import 'package:coscircle/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA email auth, onboarding, events, settings, and current flow', (
    tester,
  ) async {
    await initializeDateFormatting('zh_TW');

    final stamp = DateFormat('MMddHHmmss').format(DateTime.now());
    final nickname = 'QAUser$stamp';
    final email = 'qa_ui_$stamp@cos.test';

    appRouter.go('/login');
    await tester.pumpWidget(const ProviderScope(child: CosCircleApp()));
    await settle(tester, seconds: 3);

    expect(find.text('CosCircle'), findsWidgets);
    await tapText(tester, '註冊');
    await enterTextByLabel(tester, '暱稱', nickname);
    await enterTextByLabel(tester, 'Email', email);
    await enterTextByLabel(tester, '密碼', 'QA0714pass');
    await tapText(tester, '建立帳號');
    await settle(tester, seconds: 4);

    expect(find.text('第一次使用 CosCircle'), findsOneWidget);
    for (var i = 0; i < 3; i += 1) {
      await tapText(tester, '下一步');
    }
    await tapText(tester, '開始使用');
    await settle(tester, seconds: 4);

    expect(find.text('活動發現'), findsWidgets);

    await tapNav(tester, '名片');
    expect(find.text('Cos 名片'), findsWidgets);
    expect(find.textContaining(nickname), findsWidgets);

    await tapNav(tester, '設定');
    expect(find.text('設定'), findsWidgets);
    expect(find.text('連線狀態'), findsOneWidget);
    await tapText(tester, '連線狀態');
    await settle(tester, seconds: 4);
    expect(find.text('後端連線正常'), findsOneWidget);
    await goBack(tester);

    await tapNav(tester, '現場');
    expect(find.text('目前無當前活動'), findsWidgets);
    expect(find.text('去活動清單'), findsOneWidget);
  });
}

Future<void> settle(WidgetTester tester, {int seconds = 1}) async {
  for (var i = 0; i < seconds * 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.tap(finder.last);
  await settle(tester);
}

Future<void> enterTextByLabel(
  WidgetTester tester,
  String label,
  String value,
) async {
  final finder = find.widgetWithText(TextField, label);
  await tester.ensureVisible(finder.last);
  await tester.tap(finder.last);
  await tester.enterText(finder.last, value);
  await settle(tester);
}

Future<void> tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settle(tester, seconds: 2);
}

Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('返回').last);
  await settle(tester);
}
