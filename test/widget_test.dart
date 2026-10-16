import 'package:coscircle/app/cos_circle_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('CosCircle launches to login page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: CosCircleApp()));
    await tester.pumpAndSettle();

    expect(find.text('CosCircle'), findsOneWidget);
    expect(find.text('Cos小圈圈'), findsOneWidget);
    expect(find.text('登入'), findsWidgets);
    expect(find.text('註冊'), findsOneWidget);
  });
}
