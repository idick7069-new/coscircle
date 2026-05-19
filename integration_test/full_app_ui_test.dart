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

  testWidgets('QA profile event booking and current map flow', (tester) async {
    await initializeDateFormatting('zh_TW');

    final stamp = DateFormat('MMddHHmmss').format(DateTime.now());
    final nickname = 'QA測試員$stamp';
    final activeEvent = 'QA當前活動$stamp';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    appRouter.go('/login');
    await tester.pumpWidget(const ProviderScope(child: CosCircleApp()));
    await settle(tester);

    await tapText(tester, '使用 Google 登入');
    await enterTextByLabel(tester, '暱稱', nickname);
    await tapText(tester, '進入 Cos小圈圈');
    await settle(tester);
    expect(find.text('尚未選擇當前活動'), findsWidgets);

    await tapNav(tester, Icons.person_outline);
    expect(find.text('個人資訊'), findsOneWidget);
    await enterTextByLabel(tester, 'Facebook 網址', 'https://facebook.com/qa');
    await enterTextByLabel(tester, '自我介紹', 'QA full flow bio');
    await tapText(tester, '儲存');
    await settle(tester);
    expect(find.text('已同步更新個人資訊'), findsOneWidget);

    await tapNav(tester, Icons.menu);
    await tapText(tester, '後台管理');
    await settle(tester, seconds: 3);
    expect(find.text('後台管理'), findsOneWidget);
    expect(find.text('使用者'), findsOneWidget);
    expect(find.text('活動'), findsWidgets);

    await tapText(tester, '新增活動');
    await enterTextByLabel(tester, '活動名稱', activeEvent);
    await enterTextByLabel(tester, '分類', 'QA');
    await enterTextByLabel(tester, '開始日期 yyyy-MM-dd', today);
    await enterTextByLabel(tester, '結束日期 yyyy-MM-dd', today);
    await enterTextByLabel(tester, '地點', 'QA測試會場');
    await enterTextByLabel(tester, '費用', '免費');
    await enterTextByLabel(tester, '主辦單位', 'QA Team');
    await enterTextByLabel(tester, '活動描述', 'QA 自動測試建立的當前活動');
    await tapText(tester, '建立');
    await settle(tester, seconds: 2);
    expect(find.text(activeEvent), findsWidgets);

    await goBack(tester);
    await tapNav(tester, Icons.event_outlined);
    await settle(tester, seconds: 3);
    expect(find.text('活動清單'), findsOneWidget);
    await scrollUntilText(tester, activeEvent);
    expect(find.text(activeEvent), findsWidgets);
    await tapText(tester, '加入');
    await settle(tester);
    expect(find.text('新增預訂'), findsOneWidget);
    await enterTextByLabel(tester, '角色名', 'QA角色');
    await enterTextByLabel(tester, '想說的話', 'QA 預訂留言');
    await tapText(tester, '加入活動');
    await settle(tester, seconds: 2);

    await scrollUntilText(tester, activeEvent);
    await tapText(tester, '修改');
    await settle(tester);
    expect(find.text('修改預訂'), findsOneWidget);
    await tapText(tester, '儲存修改');
    await settle(tester, seconds: 3);

    await scrollUntilText(tester, activeEvent);
    await tapText(tester, activeEvent);
    await settle(tester, seconds: 3);
    expect(find.text('分享位置'), findsOneWidget);
    expect(find.textContaining('活動 '), findsWidgets);
  });

  testWidgets('QA social settings and submission review flow', (tester) async {
    await initializeDateFormatting('zh_TW');

    final stamp = DateFormat('MMddHHmmss').format(DateTime.now());
    final nickname = 'QA社交測試員$stamp';
    final submittedEvent = 'QA投稿活動$stamp';
    final circleName = 'QA小圈圈$stamp';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    appRouter.go('/login');
    await tester.pumpWidget(const ProviderScope(child: CosCircleApp()));
    await settle(tester);

    await tapText(tester, '使用 Google 登入');
    await enterTextByLabel(tester, '暱稱', nickname);
    await tapText(tester, '進入 Cos小圈圈');
    await settle(tester);

    await tapNav(tester, Icons.groups_outlined);
    expect(find.text('社交'), findsWidgets);
    await tapText(tester, '新建小圈圈');
    await enterTextByLabel(tester, '小圈圈名稱', circleName);
    await tapText(tester, '建立');
    await settle(tester, seconds: 2);
    expect(find.text(circleName), findsOneWidget);
    await tapPopupMenu(tester);
    await tapText(tester, '離開');
    await tapText(tester, '離開');
    await settle(tester, seconds: 2);
    expect(find.text('已離開小圈圈'), findsOneWidget);

    await tapNav(tester, Icons.menu);
    expect(find.text('其他'), findsWidgets);
    expect(find.text('BUG回報'), findsOneWidget);
    await tapText(tester, '投稿活動');
    await enterTextByLabel(tester, '活動名稱', submittedEvent);
    await enterTextByLabel(tester, '開始日期 yyyy-MM-dd', today);
    await enterTextByLabel(tester, '結束日期 yyyy-MM-dd', today);
    await enterTextByLabel(tester, '活動地點', 'QA投稿會場');
    await enterTextByLabel(tester, '活動說明', 'QA 投稿審核流程');
    await tapText(tester, '送出審核');
    await settle(tester, seconds: 2);
    expect(find.text('已送出投稿，等待管理者審核'), findsOneWidget);

    await tapText(tester, '後台管理');
    await settle(tester, seconds: 3);
    await scrollUntilText(tester, submittedEvent);
    expect(find.text('待審'), findsWidgets);
    await tapText(tester, '核准上架');
    await settle(tester, seconds: 3);
    expect(find.text(submittedEvent), findsWidgets);
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

Future<void> tapNav(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon).last);
  await settle(tester, seconds: 2);
}

Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('返回').last);
  await settle(tester);
}

Future<void> tapPopupMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>).last);
  await settle(tester);
}

Future<void> scrollUntilText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (tester.any(finder)) {
    await tester.ensureVisible(finder.last);
    return;
  }

  for (var i = 0; i < 20 && !tester.any(find.byType(Scrollable)); i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final scrollable = find.byType(Scrollable).last;
  await tester.scrollUntilVisible(
    finder,
    420,
    scrollable: scrollable,
    maxScrolls: 24,
  );
  await tester.ensureVisible(finder.last);
}
