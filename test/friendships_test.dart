import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/event_day_item.dart';
import 'package:coscircle/core/models/friendship.dart';
import 'package:coscircle/core/providers/event_providers.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/features/social/presentation/friendship_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const intro = '我是戴黑色帽子在水池旁拍照的攝影';
const incoming = Friendship(
  id: '1',
  userId: '2',
  publicCode: 'public-two',
  nickname: '戴黑帽子的攝影',
  status: 'incoming',
  introduction: intro,
  requesterId: '2',
  eventId: '10',
  dayIndex: 2,
  eventName: 'CCF',
  eventDate: '2026-10-10',
);

class FriendRepository extends SocialRepository {
  FriendRepository({this.fail = false, this.items = const []})
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  final bool fail;
  List<Friendship> items;
  final invitations = <Map<String, Object?>>[];
  final responses = <bool>[];
  @override
  Future<List<Friendship>> fetchFriendships() async => items;
  @override
  Future<String> inviteFriend(
    String userId, {
    required String introduction,
    String? eventId,
    int? dayIndex,
  }) async {
    invitations.add({
      'userId': userId,
      'introduction': introduction,
      'eventId': eventId,
      'dayIndex': dayIndex,
    });
    if (fail) throw Exception('網路中斷，請重試');
    return 'pending';
  }

  @override
  Future<void> respondFriend(String requestId, {required bool accept}) async {
    responses.add(accept);
    items = [];
  }
}

final event = CosEvent(
  id: '10',
  name: 'CCF',
  category: '展覽',
  startDate: DateTime(2026, 10, 9),
  endDate: DateTime(2026, 10, 11),
  venue: '場地',
  detailedAddress: '',
  fee: '',
  organizer: '',
  description: '',
  hasFriends: true,
  friendDayIndexes: [2],
);

void main() {
  Future<void> open(
    WidgetTester tester,
    FriendRepository repository,
    Widget body, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'fixture'});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(repository),
          eventsProvider.overrideWith((ref) async => [event]),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: body),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('friend day flags stay independent and copyWith preserves them', () {
    final days = expandEventDays([event.copyWith(isJoined: true)]);
    expect(days.map((day) => day.hasFriends), [false, true, false]);
    final fromJson = Friendship.fromJson({
      'id': 1,
      'userId': 2,
      'requesterId': 2,
      'status': 'accepted',
      'dayIndex': 2,
      'introduction': intro,
      'eventName': 'CCF',
      'eventDate': '2026-10-10',
    });
    expect(fromJson.introductionIsMine, false);
    expect(fromJson.eventLabel, 'CCF · D2 · 2026-10-10');
    expect(fromJson.isAccepted, true);
  });

  testWidgets('QR/profile offers an independent friend action', (tester) async {
    final repository = FriendRepository();
    await open(
      tester,
      repository,
      ProfileFriendshipActions(userId: '2', requireLogin: () async => true),
    );
    expect(find.text('戳友'), findsOneWidget);
    await tester.tap(find.text('戳友'));
    await tester.pumpAndSettle();
    expect(find.text('簡短自我介紹'), findsOneWidget);
    expect(find.text('認識的場次'), findsOneWidget);
    expect(repository.invitations, isEmpty);
  });

  testWidgets(
    'empty introduction is blocked, then D2 invitation preserves its exact note',
    (tester) async {
      final repository = FriendRepository();
      await open(
        tester,
        repository,
        ProfileFriendshipActions(
          userId: '2',
          requireLogin: () async => true,
          eventId: '10',
          dayIndex: 2,
        ),
      );
      await tester.tap(find.text('戳友'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('送出邀請'));
      await tester.pumpAndSettle();
      expect(repository.invitations, isEmpty);
      expect(find.text('請留下方便辨認的介紹'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, intro);
      await tester.tap(find.text('送出邀請'));
      await tester.pumpAndSettle();
      expect(repository.invitations, [
        {'userId': '2', 'introduction': intro, 'eventId': '10', 'dayIndex': 2},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failure keeps introduction and selected event for retry', (
    tester,
  ) async {
    final repository = FriendRepository(fail: true);
    await open(
      tester,
      repository,
      ProfileFriendshipActions(
        userId: '2',
        requireLogin: () async => true,
        eventId: '10',
        dayIndex: 2,
      ),
    );
    await tester.tap(find.text('戳友'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, intro);
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(find.text('網路中斷，請重試'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      intro,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('incoming invitation can be ignored and disappears from inbox', (
    tester,
  ) async {
    final repository = FriendRepository(items: [incoming]);
    await open(tester, repository, const FriendshipList());
    expect(find.text(intro), findsOneWidget);
    expect(find.text('CCF · D2 · 2026-10-10'), findsOneWidget);
    await tester.tap(find.text('忽略'));
    await tester.pumpAndSettle();
    expect(repository.responses, [false]);
    expect(find.text('目前沒有新邀請'), findsOneWidget);
  });

  testWidgets('confirmation requires an explicit tap and refreshes the inbox', (
    tester,
  ) async {
    final repository = FriendRepository(items: [incoming]);
    await open(tester, repository, const FriendshipList());
    expect(repository.responses, isEmpty);
    await tester.tap(find.text('確認戳友'));
    await tester.pumpAndSettle();
    expect(repository.responses, [true]);
    expect(find.text('目前沒有新邀請'), findsOneWidget);
  });

  testWidgets(
    'long notes and narrow screens with larger text do not overflow',
    (tester) async {
      final long = Friendship(
        id: '2',
        userId: '2',
        publicCode: '',
        nickname: List.filled(8, '很長的攝影暱稱').join(),
        status: 'incoming',
        introduction: List.filled(15, '在水池旁戴黑帽子的攝影').join(),
        requesterId: '2',
        eventName: List.filled(12, '很長的活動名稱').join(),
        eventDate: '2026-10-10',
        dayIndex: 2,
      );
      await open(
        tester,
        FriendRepository(items: [long]),
        const FriendshipList(),
        size: const Size(320, 640),
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
