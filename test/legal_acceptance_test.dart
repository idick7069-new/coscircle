import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/legal_repository.dart';
import 'package:coscircle/core/services/auth_state.dart';
import 'package:coscircle/features/safety/presentation/legal_acceptance_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _legal(
  bool accepted, {
  String version = legalVersion,
  int status = 200,
}) => ResponseBody.fromString(
  jsonEncode({'version': version, 'accepted': accepted}),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Content extends StatefulWidget {
  const _Content(this.onMount);
  final VoidCallback onMount;
  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('社群內容'));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'A'});
    sessionExpired.value = false;
  });

  Future<ApiClient> open(
    WidgetTester tester,
    _Adapter adapter, {
    VoidCallback? mount,
    bool pending = false,
  }) async {
    final api = ApiClient(baseUrl: 'https://api.invalid/api', adapter: adapter);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              LegalAcceptanceGate(child: _Content(mount ?? () {})),
        ),
        GoRoute(
          path: '/delete-account',
          builder: (_, _) => const Scaffold(body: Text('刪除入口')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('登入')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (pending) {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    } else {
      await tester.pumpAndSettle();
    }
    return api;
  }

  for (final accepted in [true, false]) {
    testWidgets(
      'pending legal status shows only loading before accepted=$accepted resolves',
      (tester) async {
        final response = Completer<ResponseBody>();
        final adapter = _Adapter((_) => response.future);
        await open(tester, adapter, pending: true);
        expect(adapter.requests.single.path, '/me/legal');
        expect(find.text('閱讀並確認使用規則'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.text('同意並繼續'), findsNothing);
        expect(find.text('社群內容'), findsNothing);
        response.complete(_legal(accepted));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('社群內容'), accepted ? findsOneWidget : findsNothing);
        expect(
          find.text('閱讀並確認使用規則'),
          accepted ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'requires explicit unchecked consent and server acknowledgment before building content',
    (tester) async {
      var mounts = 0;
      final adapter = _Adapter((request) => _legal(request.method == 'POST'));
      await open(tester, adapter, mount: () => mounts++);
      expect(mounts, 0);
      expect(find.text('社群內容'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      final button = find.byWidgetPredicate((widget) => widget is FilledButton);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(find.text('同意並繼續'));
      await tester.tap(find.text('同意並繼續'));
      await tester.pumpAndSettle();
      expect(mounts, 1);
      expect(find.text('社群內容'), findsOneWidget);
      expect(adapter.requests.last.data, {
        'version': legalVersion,
        'accepted': true,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed or incompatible status stays closed but legal reading and deletion remain accessible',
    (tester) async {
      final adapter = _Adapter((_) => _legal(true, version: 'future-version'));
      await open(tester, adapter);
      expect(find.text('社群內容'), findsNothing);
      expect(find.textContaining('更新 App'), findsOneWidget);
      await tester.ensureVisible(find.text('閱讀隱私政策'));
      await tester.tap(find.text('閱讀隱私政策'));
      await tester.pumpAndSettle();
      expect(find.text('隱私政策'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('刪除帳號'));
      await tester.tap(find.text('刪除帳號'));
      await tester.pumpAndSettle();
      expect(find.text('刪除入口'), findsOneWidget);
      expect(adapter.requests.length, 1);
    },
  );

  testWidgets('background legal refresh preserves the existing page state', (
    tester,
  ) async {
    var mounts = 0;
    Completer<ResponseBody>? refresh;
    final adapter = _Adapter((_) => refresh?.future ?? _legal(true));
    await open(tester, adapter, mount: () => mounts++);
    expect(mounts, 1);
    refresh = Completer<ResponseBody>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('社群內容'), findsOneWidget);
    refresh.complete(_legal(true));
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(find.text('社群內容'), findsOneWidget);
  });

  testWidgets('old status response never authorizes a replacement account', (
    tester,
  ) async {
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((_) => pending.future);
    final api = await open(tester, adapter, pending: true);
    await api.persistAuthToken('B');
    pending.complete(_legal(true));
    await tester.pumpAndSettle();
    expect(find.text('社群內容'), findsNothing);
    expect(await api.restoreAuthToken(), 'B');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'newer server policy closes an accepted gate on background refresh',
    (tester) async {
      var incompatible = false;
      final adapter = _Adapter(
        (_) => _legal(
          true,
          version: incompatible ? 'future-version' : legalVersion,
        ),
      );
      await open(tester, adapter);
      expect(find.text('社群內容'), findsOneWidget);
      incompatible = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('社群內容'), findsNothing);
      expect(find.textContaining('更新 App'), findsOneWidget);
    },
  );

  testWidgets(
    'switching accounts immediately hides previously accepted content',
    (tester) async {
      final api = await open(tester, _Adapter((_) => _legal(true)));
      expect(find.text('社群內容'), findsOneWidget);
      api.setAuthToken('B');
      await tester.pump();
      expect(find.text('社群內容'), findsNothing);
      expect(find.textContaining('登入狀態已變更'), findsOneWidget);
    },
  );
}
