import 'dart:async';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/circle.dart';
import 'package:coscircle/core/models/friendship.dart';
import 'package:coscircle/core/models/partner_work.dart';
import 'package:coscircle/core/models/same_work_user.dart';
import 'package:coscircle/core/providers/event_providers.dart';
import 'package:coscircle/core/providers/partner_discovery_providers.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/features/social/presentation/partner_discovery_page.dart';
import 'package:coscircle/features/social/presentation/social_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const work = PartnerWork(
  id: 'work-1',
  name: '測試作品',
  partnerCount: 2,
  isMine: true,
);
const peer = SameWorkUser(
  userId: 'peer',
  publicCode: 'public-peer',
  nickname: '公開暱稱',
  bio: '公開自我介紹',
  commonWorkCount: 0,
  commonWorks: [],
);
typedef WorkRequest = ({PartnerWorkScope scope, String q, int offset});

class DiscoveryRepository extends SocialRepository {
  DiscoveryRepository()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final requests = <WorkRequest>[];
  final userRequests = <({String workId, int offset})>[];
  final invitations = <String>[];
  List<Friendship> friends = [];
  Future<PartnerWorkPage> Function(WorkRequest)? works;
  Future<SameWorkPage> Function(String, int)? users;

  @override
  Future<PartnerWorkPage> fetchPartnerWorks({
    required PartnerWorkScope scope,
    String q = '',
    int offset = 0,
  }) {
    final request = (scope: scope, q: q, offset: offset);
    requests.add(request);
    return works?.call(request) ??
        Future.value(const PartnerWorkPage(items: [work]));
  }

  @override
  Future<SameWorkPage> fetchPartnerWorkUsers(String workId, {int offset = 0}) {
    userRequests.add((workId: workId, offset: offset));
    return users?.call(workId, offset) ??
        Future.value(const SameWorkPage(items: [peer]));
  }

  @override
  Future<List<Friendship>> fetchFriendships() async => friends;

  @override
  Future<String> inviteFriend(
    String userId, {
    required String introduction,
    String? eventId,
    int? dayIndex,
  }) async {
    invitations.add(userId);
    return 'pending';
  }
}

class RecordingClient extends ApiClient {
  RecordingClient() : super(baseUrl: 'https://example.invalid/api');
  final calls = <({String path, Map<String, dynamic>? query})>[];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    ApiSession? session,
  }) async {
    calls.add((path: path, query: query));
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: {'items': <dynamic>[], 'hasMore': false, 'nextOffset': null},
    );
  }
}

Future<GoRouter> openDiscovery(
  WidgetTester tester,
  DiscoveryRepository repository, {
  Widget body = const PartnerDiscoveryPage(),
  double width = 360,
  double height = 900,
  double scale = 1,
  List<CircleGroup> circles = const [],
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: body),
      ),
      GoRoute(
        path: '/profiles/:code',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('名片 ${state.pathParameters['code']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialRepositoryProvider.overrideWithValue(repository),
        apiClientProvider.overrideWithValue(RecordingClient()),
        eventsProvider.overrideWith((ref) async => <CosEvent>[]),
        circlesProvider.overrideWith((ref) async => circles),
        followingProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).hitTestable(), text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  for (final (width, scale) in [
    (320.0, 1.0),
    (360.0, 1.0),
    (320.0, 2.0),
    (360.0, 2.0),
  ]) {
    testWidgets(
      'four social tabs share width and preserve content proportions at $width text $scale',
      (tester) async {
        await openDiscovery(
          tester,
          DiscoveryRepository(),
          height: scale == 1 ? 600 : 900,
          width: width,
          scale: scale,
          body: const Padding(
            padding: EdgeInsets.only(bottom: 92),
            child: SocialPage(),
          ),
        );
        final bar = find.byType(TabBar).first;
        final tabs = find.descendant(of: bar, matching: find.byType(InkWell));
        final rectangles = tester
            .widgetList<InkWell>(tabs)
            .toList()
            .asMap()
            .keys
            .map((index) => tester.getRect(tabs.at(index)))
            .toList();
        expect(rectangles.length, 4);
        for (final rectangle in rectangles) {
          expect(rectangle.width, closeTo(rectangles.first.width, 0.1));
          expect(rectangle.left, greaterThanOrEqualTo(0));
          expect(rectangle.right, lessThanOrEqualTo(width));
        }
        final initial = tester.getRect(find.byType(TabBarView).first);
        for (final label in ['已關注', '戳友', '尋找夥伴']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          expect(find.text('同好小圈圈'), findsOneWidget);
          expect(tester.getRect(find.byType(TabBarView).first), initial);
        }
        await tester.tap(find.text('小圈圈').first);
        await tester.pumpAndSettle();
        expect(find.text('同好小圈圈'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('expanded circle leaves space above invitation band', (
    tester,
  ) async {
    await openDiscovery(
      tester,
      DiscoveryRepository(),
      height: 1200,
      body: const SocialPage(),
      circles: const [
        CircleGroup(
          id: 'spacing',
          name: '間距測試圈',
          inviteCode: 'TEST123',
          inviteUrl: '',
          memberCount: 0,
          isOwner: false,
          members: [],
        ),
      ],
    );
    await tester.ensureVisible(find.text('間距測試圈'));
    await tester.tap(find.text('間距測試圈'));
    await tester.pumpAndSettle();
    final header = find
        .ancestor(of: find.text('間距測試圈'), matching: find.byType(InkWell))
        .first;
    final band = find
        .ancestor(of: find.text('邀請碼'), matching: find.byType(DecoratedBox))
        .first;
    expect(
      tester.getRect(band).top - tester.getRect(header).bottom,
      greaterThanOrEqualTo(16),
    );
    expect(find.byTooltip('顯示邀請 QRCode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'repository preserves the contract and literal search without HTTP',
    () async {
      final client = RecordingClient();
      final repository = SocialRepository(apiClient: client);
      await repository.fetchPartnerWorks(
        scope: PartnerWorkScope.mine,
        q: '%_\\',
        offset: 20,
      );
      await repository.fetchPartnerWorks(scope: PartnerWorkScope.all);
      await repository.fetchPartnerWorkUsers('id/with space', offset: 40);
      expect(client.calls[0].path, '/social/partner-works');
      expect(client.calls[0].query, {
        'scope': 'mine',
        'q': '%_\\',
        'offset': 20,
        'limit': 20,
      });
      expect(client.calls[1].query, {
        'scope': 'all',
        'q': '',
        'offset': 0,
        'limit': 20,
      });
      expect(
        client.calls[2].path,
        '/social/partner-works/id%2Fwith%20space/users',
      );
      expect(client.calls[2].query, {'offset': 40, 'limit': 20});
      final page = PartnerWorkPage.fromJson({
        'items': [
          {'id': 'zero', 'name': '零位夥伴', 'partnerCount': 0, 'isMine': true},
        ],
        'hasMore': true,
        'nextOffset': 20,
      });
      expect(page.items.single.partnerCount, 0);
      expect(page.items.single.isMine, true);
      expect(page.nextOffset, 20);
    },
  );

  testWidgets('exact two tabs retain independent submitted literal queries', (
    tester,
  ) async {
    final repository = DiscoveryRepository();
    await openDiscovery(tester, repository);
    expect(find.byType(Tab), findsNWidgets(2));
    expect(find.text('與我同坑'), findsOneWidget);
    expect(find.text('看看大家坑什麼'), findsOneWidget);
    await search(tester, '%_作品');
    expect(repository.requests.last.q, '%_作品');
    expect(repository.requests.last.scope, PartnerWorkScope.mine);
    await tester.tap(find.text('看看大家坑什麼'));
    await tester.pumpAndSettle();
    await search(tester, '大家');
    expect(repository.requests.last, (
      scope: PartnerWorkScope.all,
      q: '大家',
      offset: 0,
    ));
    await tester.tap(find.text('與我同坑'));
    await tester.pumpAndSettle();
    expect(find.text('%_作品'), findsOneWidget);
    expect(find.text('我的坑').hitTestable(), findsOneWidget);
    expect(find.text('2 位夥伴').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'work opens public people and profile, zero common count has no claim',
    (tester) async {
      final repository = DiscoveryRepository();
      final router = await openDiscovery(tester, repository);
      await tester.tap(find.text('測試作品').hitTestable());
      await tester.pumpAndSettle();
      expect(repository.userRequests, [(workId: 'work-1', offset: 0)]);
      expect(find.text('公開暱稱'), findsOneWidget);
      expect(find.text('公開自我介紹'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.textContaining('共同作品'), findsNothing);
      await tester.tap(find.text('查看名片'));
      await tester.pumpAndSettle();
      expect(find.text('名片 public-peer'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('戳友'));
      await tester.pumpAndSettle();
      expect(find.text('戳友邀請'), findsOneWidget);
      expect(repository.invitations, isEmpty);
    },
  );

  testWidgets(
    'loading, retry and empty mine do not imply another profile route',
    (tester) async {
      final pending = Completer<PartnerWorkPage>();
      final repository = DiscoveryRepository()..works = (_) => pending.future;
      await openDiscovery(tester, repository);
      expect(find.text('載入中').hitTestable(), findsOneWidget);
      expect(find.text('你的坑單還沒有作品'), findsNothing);
      pending.completeError(Exception('暫時失敗'));
      await tester.pump();
      await tester.pump();
      expect(find.text('重試').hitTestable(), findsOneWidget);
      repository.works = (_) async => const PartnerWorkPage(items: []);
      await tester.tap(find.text('重試').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('你的坑單還沒有作品').hitTestable(), findsOneWidget);
      expect(find.text('查看名片'), findsNothing);
      await search(tester, '不存在');
      expect(find.text('沒有符合搜尋的作品').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('load more failure keeps works and retry appends unique items', (
    tester,
  ) async {
    var fail = true;
    final repository = DiscoveryRepository()
      ..works = (request) async {
        if (request.offset == 0) {
          return const PartnerWorkPage(items: [work], nextOffset: 20);
        }
        if (fail) throw Exception('暫時失敗');
        return const PartnerWorkPage(
          items: [
            work,
            PartnerWork(id: 'next', name: '下一部', partnerCount: 0, isMine: true),
          ],
        );
      };
    await openDiscovery(tester, repository);
    await tester.tap(find.text('載入更多').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('測試作品').hitTestable(), findsOneWidget);
    expect(find.text('重試載入更多').hitTestable(), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重試載入更多').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('測試作品').hitTestable(), findsOneWidget);
    expect(find.text('下一部').hitTestable(), findsOneWidget);
    expect(find.text('0 位夥伴').hitTestable(), findsOneWidget);
    expect(repository.requests.last.offset, 20);
  });

  testWidgets('late search responses cannot replace the current query', (
    tester,
  ) async {
    final slow = Completer<PartnerWorkPage>();
    final repository = DiscoveryRepository()
      ..works = (request) async {
        if (request.q == 'slow') return slow.future;
        return PartnerWorkPage(
          items: [
            PartnerWork(
              id: request.q,
              name: '結果 ${request.q}',
              partnerCount: 1,
              isMine: true,
            ),
          ],
        );
      };
    await openDiscovery(tester, repository);
    await search(tester, 'slow');
    await search(tester, 'fast');
    expect(find.text('結果 fast').hitTestable(), findsOneWidget);
    slow.complete(const PartnerWorkPage(items: [work]));
    await tester.pumpAndSettle();
    expect(find.text('結果 fast').hitTestable(), findsOneWidget);
    expect(find.text('測試作品'), findsNothing);
  });

  testWidgets(
    'people retry, pagination and empty refresh preserve the right state',
    (tester) async {
      var failFirst = true;
      var failMore = true;
      var empty = false;
      final repository = DiscoveryRepository()
        ..users = (_, offset) async {
          if (failFirst) throw Exception('成員載入失敗');
          if (empty) return const SameWorkPage(items: []);
          if (offset == 0) {
            return const SameWorkPage(items: [peer], nextOffset: 20);
          }
          if (failMore) throw Exception('分頁載入失敗');
          return const SameWorkPage(
            items: [
              peer,
              SameWorkUser(
                userId: 'next-peer',
                publicCode: 'next-code',
                nickname: '下一位夥伴',
                commonWorks: [],
                commonWorkCount: 1,
              ),
            ],
          );
        };
      await openDiscovery(
        tester,
        repository,
        body: const PartnerWorkPeoplePage(work: work),
      );
      expect(find.text('重試'), findsOneWidget);
      failFirst = false;
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('載入更多'));
      await tester.pumpAndSettle();
      expect(find.text('公開暱稱'), findsOneWidget);
      expect(find.text('重試載入更多'), findsOneWidget);
      failMore = false;
      await tester.tap(find.text('重試載入更多'));
      await tester.pumpAndSettle();
      expect(find.text('下一位夥伴'), findsOneWidget);
      expect(find.text('公開暱稱'), findsOneWidget);
      expect(find.text('1 部共同作品'), findsOneWidget);
      expect(repository.userRequests.last.offset, 20);
      empty = true;
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text('這部作品目前沒有可顯示的夥伴'), findsOneWidget);
      expect(find.text('公開暱稱'), findsNothing);
    },
  );

  testWidgets(
    'accepted friendship shows status instead of another invitation',
    (tester) async {
      final repository = DiscoveryRepository()
        ..friends = [
          const Friendship(
            id: 'friend',
            userId: 'peer',
            publicCode: 'public-peer',
            nickname: '公開暱稱',
            status: 'accepted',
            introduction: '認識的同好',
            requesterId: 'peer',
          ),
        ];
      await openDiscovery(
        tester,
        repository,
        body: const PartnerWorkPeoplePage(work: work),
      );
      await tester.pumpAndSettle();
      expect(find.text('已是戳友'), findsOneWidget);
      expect(find.text('戳友'), findsNothing);
      expect(find.text('查看名片'), findsOneWidget);
    },
  );

  test(
    'session changes discard initial responses and in-flight load more',
    () async {
      final client = RecordingClient();
      final oldMore = Completer<PartnerWorkPage>();
      final oldPeople = Completer<SameWorkPage>();
      var account = 0;
      final repository = DiscoveryRepository()
        ..works = (request) async {
          if (request.offset > 0) return oldMore.future;
          return account == 0
              ? const PartnerWorkPage(items: [work], nextOffset: 20)
              : const PartnerWorkPage(items: []);
        }
        ..users = (_, _) => account == 0
            ? oldPeople.future
            : Future.value(const SameWorkPage(items: []));
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          socialRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final worksProvider = partnerWorksProvider((
        scope: PartnerWorkScope.mine,
        q: '',
      ));
      final usersProvider = partnerWorkUsersProvider(work.id);
      container.listen(worksProvider, (_, _) {});
      container.listen(usersProvider, (_, _) {});
      await container.read(worksProvider.future);
      final more = container.read(worksProvider.notifier).loadMore();
      account = 1;
      client.setAuthToken('different-session');
      await container.read(worksProvider.future);
      await container.read(usersProvider.future);
      oldMore.complete(const PartnerWorkPage(items: [work]));
      oldPeople.complete(const SameWorkPage(items: [peer]));
      await more;
      await Future<void>.delayed(Duration.zero);
      expect(container.read(worksProvider).asData!.value.items, isEmpty);
      expect(container.read(usersProvider).asData!.value.items, isEmpty);
    },
  );

  for (final width in [320.0, 360.0]) {
    testWidgets('long works and people fit $width with double text size', (
      tester,
    ) async {
      final longWork = PartnerWork(
        id: 'long',
        name: List.filled(12, '非常長的作品名稱').join(),
        partnerCount: 999999,
        isMine: true,
      );
      final repository = DiscoveryRepository();
      repository.works = (_) async => PartnerWorkPage(items: [longWork]);
      repository.users = (_, _) async => SameWorkPage(
        items: [
          SameWorkUser(
            userId: 'long',
            publicCode: 'long',
            nickname: List.filled(20, '長暱稱').join(),
            bio: List.filled(30, '公開的長篇自我介紹').join(),
            commonWorkCount: 0,
            commonWorks: [],
          ),
        ],
      );
      await openDiscovery(tester, repository, width: width, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(longWork.name).hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('查看名片'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
