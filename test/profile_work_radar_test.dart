import 'dart:async';

import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/models/work.dart';
import 'package:coscircle/core/theme/app_theme.dart';
import 'package:coscircle/features/profile/presentation/profile_work_radar.dart';
import 'package:coscircle/features/profile/presentation/public_profile_page.dart';
import 'package:coscircle/shared/widgets/cos_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class WaitingProfileRepository implements ProfileRepository {
  final requests = <Completer<UserProfile?>>[];
  final publicRequests = <Completer<UserProfile?>>[];

  @override
  Future<UserProfile?> fetchProfile(String code) {
    final request = Completer<UserProfile?>();
    publicRequests.add(request);
    return request.future;
  }

  @override
  Future<UserProfile?> currentProfile() {
    final request = Completer<UserProfile?>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const mine = UserProfile(
  id: '17',
  nickname: 'QA',
  deepPitWorks: [WorkTag(id: '1', name: '共同作品原名')],
  shallowPitWorks: [WorkTag(id: '2', name: '第二部')],
);
const peer = UserProfile(
  id: '18',
  nickname: 'QA B',
  deepPitWorks: [
    WorkTag(id: '2', name: '第二部'),
    WorkTag(id: '3', name: '獨有作品'),
  ],
  shallowPitWorks: [WorkTag(id: '1', name: '共同作品改名')],
);

void main() {
  for (final cached in [false, true]) {
    testWidgets(
      'public profile isolates ${cached ? 'cached' : 'pending'} peer across accounts',
      (tester) async {
        final client = ApiClient(baseUrl: 'https://example.invalid/api')
          ..setAuthToken('qa-A');
        final repository = WaitingProfileRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              profileRepositoryProvider.overrideWithValue(repository),
            ],
            child: const MaterialApp(
              home: PublicProfilePage(publicCode: 'peer'),
            ),
          ),
        );
        await tester.pump();
        final pendingA = repository.publicRequests.single;
        if (cached) {
          pendingA.complete(peer);
          await tester.pump();
          await tester.pump();
          expect(find.text('QA B'), findsWidgets);
        }
        client.setAuthToken('qa-B');
        await tester.pump();
        expect(find.text('QA B'), findsNothing);
        await tester.pump();
        expect(repository.publicRequests.length, 2);
        repository.publicRequests.last.complete(null);
        if (!cached) pendingA.complete(peer);
        await tester.pumpAndSettle();
        expect(find.text('QA B'), findsNothing);
        expect(find.text('找不到這張名片'), findsOneWidget);
        expect(find.textContaining('你們有'), findsNothing);
      },
    );
  }
  testWidgets(
    'account switch, logout and late old request never retain previous radar',
    (tester) async {
      final client = ApiClient(baseUrl: 'https://example.invalid/api')
        ..setAuthToken('qa-A');
      final repository = WaitingProfileRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ProfileCommonWorkNotice(profile: peer),
                    ProfileWorkRadar(profile: peer),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      repository.requests[0].complete(mine);
      await tester.pumpAndSettle();
      expect(find.textContaining('你們有 2 部'), findsOneWidget);
      client.setAuthToken('qa-B');
      await tester.pump();
      expect(find.textContaining('你們有'), findsNothing);
      expect(
        tester
            .widgetList<CosBadge>(find.byType(CosBadge))
            .any((tag) => tag.highlighted),
        isFalse,
      );
      await tester.pump();
      final pendingB = repository.requests.last;
      client.setAuthToken('qa-C');
      await tester.pump();
      await tester.pump();
      final pendingC = repository.requests.last;
      expect(pendingB, isNot(same(pendingC)));
      pendingB.complete(mine);
      await tester.pump();
      expect(find.textContaining('你們有'), findsNothing);
      pendingC.complete(mine);
      await tester.pumpAndSettle();
      expect(find.textContaining('你們有 2 部'), findsOneWidget);
      client.setAuthToken(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('你們有'), findsNothing);
      expect(
        tester
            .widgetList<CosBadge>(find.byType(CosBadge))
            .any((tag) => tag.highlighted),
        isFalse,
      );
    },
  );

  test('matches exact IDs across deep/shallow works, not labels', () {
    expect(commonProfileWorkIds(mine, peer), {'1', '2'});
    expect(
      commonProfileWorkIds(
        mine,
        const UserProfile(
          id: '18',
          nickname: 'B',
          deepPitWorks: [WorkTag(id: '99', name: '第二部')],
        ),
      ),
      isEmpty,
    );
  });

  test('guest, self and missing work IDs cannot produce a reminder', () {
    expect(commonProfileWorkIds(null, peer), isEmpty);
    expect(commonProfileWorkIds(mine, mine), isEmpty);
    expect(
      commonProfileWorkIds(
        mine,
        const UserProfile(
          id: '18',
          nickname: 'B',
          isMe: true,
          deepPitWorks: [WorkTag(id: '1', name: 'A')],
        ),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'notice counts unique shared works and highlights only matching tags',
    (tester) async {
      await tester.pumpWidget(_host(() async => mine));
      await tester.pumpAndSettle();
      expect(find.text('同坑雷達！你們有 2 部共同作品'), findsOneWidget);
      final tags = tester.widgetList<CosBadge>(find.byType(CosBadge)).toList();
      expect(
        tags.where((tag) => tag.highlighted).map((tag) => tag.label).toSet(),
        {'共同作品改名', '第二部'},
      );
      expect(
        tags.singleWhere((tag) => tag.label == '獨有作品').highlighted,
        isFalse,
      );
      expect(find.byIcon(Icons.radar), findsNWidgets(3));
    },
  );

  testWidgets('loading and failed personal data never claim no overlap', (
    tester,
  ) async {
    final waiting = Completer<UserProfile?>();
    await tester.pumpWidget(_host(() => waiting.future));
    await tester.pump();
    expect(find.textContaining('你們有'), findsNothing);
    waiting.completeError(StateError('QA unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('重新讀取同坑雷達'), findsOneWidget);
    expect(find.textContaining('你們有'), findsNothing);
    expect(find.text('共同作品改名'), findsOneWidget);
  });

  testWidgets(
    'guest still reads public tags without personalized highlighting',
    (tester) async {
      await tester.pumpWidget(_host(() async => null));
      await tester.pumpAndSettle();
      expect(find.textContaining('你們有'), findsNothing);
      expect(
        tester
            .widgetList<CosBadge>(find.byType(CosBadge))
            .every((tag) => !tag.highlighted),
        isTrue,
      );
    },
  );

  testWidgets('radar wraps at narrow width and large text in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      await tester.pumpWidget(_host(() async => mine, dark: dark, scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('同坑雷達！你們有 2 部共同作品'), findsOneWidget);
    }
  });
}

Widget _host(
  Future<UserProfile?> Function() viewer, {
  bool dark = false,
  double scale = 1,
}) {
  return ProviderScope(
    overrides: [
      radarViewerProfileProvider.overrideWith((ref, version) => viewer()),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              ProfileCommonWorkNotice(profile: peer),
              ProfileWorkRadar(profile: peer),
            ],
          ),
        ),
      ),
    ),
  );
}
