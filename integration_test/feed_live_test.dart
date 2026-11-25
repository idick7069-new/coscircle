// Dedicated production QA actors are injected only into memory. Never persist these sessions.
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/features/feed/presentation/feed_page.dart';
import 'package:coscircle/features/feed/presentation/feed_composer_page.dart';
import 'package:coscircle/features/safety/presentation/legal_acceptance_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final qa = jsonDecode(const String.fromEnvironment('FEED_QA')) as Map;
  final http = Dio(
    BaseOptions(
      baseUrl: 'https://coscircle.app/api',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  Future<dynamic> call(
    String actor,
    String path, {
    String method = 'GET',
    dynamic body,
    int status = 200,
  }) async {
    final r = await http.request(
      path,
      data: body,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer ${qa['${actor}Token']}'},
        validateStatus: (_) => true,
      ),
    );
    expect(r.statusCode, status, reason: '$actor $method $path');
    return r.data;
  }

  testWidgets(
    'production feed: consent, publish, edit, like, replies, ownership, visibility and booking sync',
    (t) async {
      GoRouter? router;
      Future<void> until(
        bool Function() ready, {
        String reason = 'UI ready',
      }) async {
        final end = DateTime.now().add(const Duration(seconds: 45));
        while (!ready() && DateTime.now().isBefore(end)) {
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(ready(), true, reason: reason);
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().isNotEmpty, reason: 'control exists');
        await t.ensureVisible(f.first);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 400));
      }

      Future<void> mount(String actor, {String? id}) async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
        router?.dispose();
        final api = ApiClient(baseUrl: 'https://coscircle.app/api')
          ..setAuthToken(qa['${actor}Token'] as String);
        router = GoRouter(
          initialLocation: id == null ? '/' : '/feed/$id',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, s) => const LegalAcceptanceGate(
                child: Scaffold(body: SafeArea(child: FeedPage())),
              ),
            ),
            GoRoute(
              path: '/feed/:id',
              builder: (_, s) => LegalAcceptanceGate(
                child: FeedDetailPage(postId: s.pathParameters['id']!),
              ),
            ),
          ],
        );
        await t.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp.router(
              theme: AppTheme.dark,
              locale: const Locale('zh', 'TW'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('zh', 'TW'), Locale('en', 'US')],
              routerConfig: router,
            ),
          ),
        );
      }

      Finder input() => find.byType(TextField).first;
      Finder send() =>
          find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '送出留言');
      Future<void> menu(String label) async {
        await tap(find.byTooltip('貼文選項'));
        await tap(find.text(label));
      }

      Future<void> audience(String id, String value) async {
        await mount('author', id: id);
        await until(() => find.byTooltip('貼文選項').evaluate().isNotEmpty);
        await menu('編輯貼文');
        final selector = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == '誰可以看到',
        );
        await tap(selector);
        await tap(find.text(value).last);
        if (value == '指定小圈圈') {
          final circle = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == '選擇小圈圈',
          );
          await tap(circle);
          await tap(find.text('[QA隔離]動態圈').last);
        }
        await tap(find.text('儲存變更'));
        await until(
          () => find.byType(FeedComposerPage).evaluate().isEmpty,
          reason: 'audience saved',
        );
      }

      await mount('author');
      await until(
        () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
        reason: 'real consent screen',
      );
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
        isNotNull,
      );
      await tap(find.byType(CheckboxListTile));
      await tap(find.text('同意並繼續'));
      await until(
        () => find.text('發貼文').evaluate().isNotEmpty,
        reason: 'consent accepted',
      );
      await tap(find.text('發貼文'));
      await until(() => find.byType(TextField).evaluate().isNotEmpty);
      final body = '[QA隔離] Android UI ${DateTime.now().millisecondsSinceEpoch}';
      await t.enterText(input(), body);
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(find.text('發佈'));
      await until(
        () =>
            find.byType(FeedComposerPage).evaluate().isEmpty &&
            find.text(body).evaluate().isNotEmpty,
        reason: 'post published via UI',
      );
      final items = (await call('author', '/feed'))['items'] as List;
      final id = items.firstWhere((p) => p['body'] == body)['id'].toString();
      await menu('編輯貼文');
      await until(() => find.byType(TextField).evaluate().isNotEmpty);
      await t.enterText(input(), '$body edited');
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(find.text('儲存變更'));
      await until(
        () =>
            find.byType(FeedComposerPage).evaluate().isEmpty &&
            find.text('$body edited').evaluate().isNotEmpty,
        reason: 'edit persisted',
      );
      expect((await call('author', '/feed/$id'))['body'], '$body edited');
      await mount('peer', id: id);
      await until(() => send().evaluate().isNotEmpty);
      expect(t.widget<IconButton>(send()).onPressed, isNull);
      await tap(find.byIcon(Icons.favorite_border));
      await until(
        () => find.byIcon(Icons.favorite).evaluate().isNotEmpty,
        reason: 'like button',
      );
      expect((await call('author', '/feed/$id'))['likeCount'], 1);
      await tap(find.byIcon(Icons.favorite));
      await until(
        () => find.byIcon(Icons.favorite_border).evaluate().isNotEmpty,
      );
      expect((await call('author', '/feed/$id'))['likeCount'], 0);
      await t.enterText(input(), 'UI peer comment');
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(send());
      await until(
        () => find.text('UI peer comment').evaluate().isNotEmpty,
        reason: 'comment sent',
      );
      await mount('author', id: id);
      await until(() => find.text('UI peer comment').evaluate().isNotEmpty);
      await tap(find.text('回覆'));
      await t.enterText(input(), 'UI author reply');
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(send());
      await until(
        () => find.text('UI author reply').evaluate().isNotEmpty,
        reason: 'reply sent',
      );
      final comments =
          (await call('author', '/feed/$id/comments'))['items'] as List;
      expect(
        comments.firstWhere((c) => c['body'] == 'UI author reply')['parentId'],
        isNotNull,
      );
      await menu('關閉留言');
      await until(() => find.text('作者已關閉留言').evaluate().isNotEmpty);
      expect(find.byTooltip('送出留言'), findsNothing);
      await call(
        'peer',
        '/feed/$id/comments',
        method: 'POST',
        body: {'body': 'must fail'},
        status: 409,
      );
      await menu('開啟留言');
      await until(
        () => send().evaluate().isNotEmpty,
        reason: 'reopen comments',
      );
      await mount('peer', id: id);
      await until(() => find.text('UI peer comment').evaluate().isNotEmpty);
      final tile = find.ancestor(
        of: find.text('UI peer comment'),
        matching: find.byType(ListTile),
      );
      await tap(find.descendant(of: tile, matching: find.byTooltip('留言選項')));
      await tap(find.text('刪除留言'));
      await tap(find.text('確認'));
      await until(
        () => find.text('UI peer comment').evaluate().isEmpty,
        reason: 'own comment deleted',
      );
      await audience(id, '戳友限定');
      await call('outsider', '/feed/$id', status: 404);
      await call('peer', '/feed/$id');
      await audience(id, '指定小圈圈');
      await call('outsider', '/feed/$id', status: 404);
      await call('peer', '/feed/$id');
      await call('ordinary', '/feed/$id', status: 404);
      // Share an existing booking using the actual composer and verify live booking changes.
      await mount('author');
      await until(() => find.text('分享預定').evaluate().isNotEmpty);
      await tap(find.text('分享預定'));
      await until(() => find.byType(TextField).evaluate().isNotEmpty);
      await t.enterText(input(), '[QA隔離] UI booking');
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(find.text('發佈'));
      await until(
        () =>
            find.byType(FeedComposerPage).evaluate().isEmpty &&
            find.text('[QA隔離] UI booking').evaluate().isNotEmpty,
        reason: 'booking shared',
      );
      final shared = await call(
        'author',
        '/feed/booking-share?eventId=${qa['eventId']}&dayIndex=1',
      );
      final bookingId = shared['id'].toString();
      await call(
        'author',
        '/events/${qa['eventId']}/bookings',
        method: 'POST',
        body: {
          'role': 'coser',
          'dayIndex': 1,
          'characterName': 'UI live updated',
        },
        status: 204,
      );
      await mount('peer', id: bookingId);
      await until(
        () => find.textContaining('UI live updated').evaluate().isNotEmpty,
        reason: 'live booking sync visible',
      );
      await call(
        'author',
        '/events/${qa['eventId']}/bookings/me?dayIndex=1',
        method: 'DELETE',
        status: 204,
      );
      await mount('peer', id: bookingId);
      await until(
        () => find.text('已取消預定').evaluate().isNotEmpty,
        reason: 'cancelled booking preserved',
      );
      await mount('author', id: id);
      await until(() => find.byTooltip('貼文選項').evaluate().isNotEmpty);
      await menu('刪除貼文');
      await tap(find.text('確認'));
      await call('author', '/feed/$id', status: 404);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      router?.dispose();
      http.close();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
