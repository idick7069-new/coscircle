import 'package:coscircle/app/cos_circle_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin dashboard loads database status on a real device', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CosCircleApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('使用 Google 登入'));
    await tester.pumpAndSettle();

    final nickname = find.byType(TextField).first;
    await tester.enterText(nickname, '實機測試員');
    await tester.tap(find.text('進入 Cos小圈圈'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('後台管理'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('後台管理'), findsOneWidget);
    expect(find.text('活動'), findsWidgets);
    expect(find.text('使用者'), findsOneWidget);
    expect(find.text('新增活動'), findsOneWidget);
  });
}
