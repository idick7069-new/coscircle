import 'package:coscircle/app/cos_circle_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('CosCircle launches to login page', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CosCircleApp()));

    expect(find.text('CosCircle'), findsOneWidget);
    expect(find.text('Cos小圈圈'), findsOneWidget);
    expect(find.text('使用 Google 登入'), findsOneWidget);
  });
}
