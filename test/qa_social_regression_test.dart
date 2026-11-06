import 'dart:async';
import 'package:coscircle/core/api/api_client.dart';

import 'package:coscircle/core/models/booking_visibility.dart';
import 'package:coscircle/core/models/circle.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/friendship.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/models/same_work_user.dart';
import 'package:coscircle/core/providers/event_providers.dart';
import 'package:coscircle/core/providers/friendship_providers.dart';
import 'package:coscircle/core/providers/same_work_providers.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/features/profile/presentation/profile_page.dart';
import 'package:coscircle/features/profile/presentation/public_profile_page.dart';
import 'package:coscircle/features/social/presentation/friendship_widgets.dart';
import 'package:coscircle/features/social/presentation/social_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alpha_regression_test.dart' as qa;
import 'friendships_test.dart' as friends;

class _Relationships {
  bool followed = false;
  bool blocked = false;
  bool fail = false;
  String? friendshipStatus = 'accepted';
  final responses = <bool>[];
  final removals = <String>[];
  final invitations = <Map<String, Object?>>[];
}

class _Profile extends qa.FixtureProfile {
  _Profile(this.state);
  final _Relationships state;

  @override
  Future<UserProfile?> fetchProfile(String publicCode) async => state.blocked
      ? null
      : UserProfile(
          id: '2',
          publicCode: publicCode,
          nickname: '測試同好',
          isFollowed: state.followed,
        );

  @override
  Future<void> followUser(String userId) async {
    if (state.fail) throw Exception('關注失敗');
    state.followed = true;
  }

  @override
  Future<void> unfollowUser(String userId) async {
    if (state.fail) throw Exception('關注失敗');
    state.followed = false;
  }

  @override
  Future<void> blockUser(String userId) async {
    if (state.fail) throw Exception('封鎖失敗');
    state.blocked = true;
    state.followed = false;
  }

  @override
  Future<void> unblockUser(String userId) async {
    state.blocked = false;
  }

  @override
  Future<List<BlockedUser>> fetchBlockedUsers() async => state.blocked
      ? const [BlockedUser(userId: '2', nickname: '測試同好')]
      : const [];

  @override
  Future<List<BookingFollowerGroup>> fetchBookingFollowers() async =>
      state.blocked
      ? []
      : [
          BookingFollowerGroup(
            bookingId: 'booking',
            eventId: 'qa',
            eventName: 'QA',
            startDate: friends.event.startDate,
            endDate: friends.event.endDate,
            dayIndex: 1,
            role: 'coser',
          ),
        ];
}

class _Social extends qa.FixtureSocial {
  _Social(this.state);
  final _Relationships state;

  @override
  Future<List<FollowedUser>> fetchFollowing() async => state.followed
      ? const [FollowedUser(userId: '2', publicCode: 'peer', nickname: '測試同好')]
      : const [];

  @override
  Future<List<CircleGroup>> fetchCircles() async => [
    CircleGroup(
      id: 'qa',
      name: 'QA circle',
      inviteCode: 'QA123',
      inviteUrl: '',
      memberCount: 2,
      isOwner: true,
      members: state.blocked
          ? []
          : const [
              CircleMember(userId: '2', publicCode: 'peer', nickname: '測試同好'),
            ],
    ),
  ];

  @override
  Future<List<Friendship>> fetchFriendships() async =>
      state.blocked || state.friendshipStatus == null
      ? const []
      : [
          Friendship(
            id: friends.incoming.id,
            userId: '2',
            publicCode: 'peer',
            nickname: '測試同好',
            status: state.friendshipStatus!,
            introduction: friends.intro,
            requesterId: '2',
          ),
        ];

  @override
  Future<void> respondFriend(String requestId, {required bool accept}) async {
    if (state.fail) throw Exception('社交操作失敗');
    state.responses.add(accept);
    state.friendshipStatus = accept ? 'accepted' : null;
  }

  @override
  Future<void> removeFriend(String userId) async {
    if (state.fail) throw Exception('社交操作失敗');
    state.removals.add(userId);
    state.friendshipStatus = null;
  }

  @override
  Future<String> inviteFriend(
    String userId, {
    required String introduction,
    String? eventId,
    int? dayIndex,
  }) async {
    if (state.fail) throw Exception('社交操作失敗');
    state.invitations.add({
      'userId': userId,
      'introduction': introduction,
      'eventId': eventId,
      'dayIndex': dayIndex,
    });
    state.friendshipStatus = 'pending';
    return 'pending';
  }

  @override
  Future<SameWorkPage> fetchSameWorkUsers({int offset = 0}) async =>
      SameWorkPage(
        items: state.blocked
            ? []
            : const [
                SameWorkUser(
                  userId: '2',
                  publicCode: 'peer',
                  nickname: '測試同好',
                  commonWorkCount: 1,
                  commonWorks: [],
                ),
              ],
      );
}

class _Events extends qa.FixtureEvents {
  _Events(this.state);
  final _Relationships state;

  @override
  Future<List<CosEvent>> fetchEvents() async => [
    CosEvent(
      id: friends.event.id,
      name: friends.event.name,
      category: friends.event.category,
      startDate: friends.event.startDate,
      endDate: friends.event.endDate,
      venue: friends.event.venue,
      detailedAddress: '',
      fee: '',
      organizer: '',
      description: '',
      followedDayIndexes: state.followed ? [2] : [],
      hasFriends: !state.blocked && state.friendshipStatus == 'accepted',
      friendDayIndexes: !state.blocked && state.friendshipStatus == 'accepted'
          ? [2]
          : [],
    ),
  ];

  @override
  Future<List<EventParticipant>> fetchParticipants(String id) async =>
      state.blocked
      ? []
      : [
          EventParticipant(
            userId: '2',
            nickname: '測試同好',
            role: 'coser',
            isFollowed: state.followed,
          ),
        ];
}

// Keep each affected cache observed across the mutation, as retained tabs do.
class _CachedViews extends ConsumerWidget {
  const _CachedViews();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followingProvider).asData?.value;
    final circles = ref.watch(circlesProvider).asData?.value;
    final blocked = ref.watch(blockedUsersProvider).asData?.value;
    final followers = ref.watch(bookingFollowersProvider).asData?.value;
    final friendships = ref.watch(friendshipsProvider).asData?.value;
    final sameWorks = ref.watch(sameWorkUsersProvider).asData?.value;
    final events = ref.watch(eventsProvider).asData?.value;
    final first = ref.watch(eventParticipantsProvider('10')).asData?.value;
    final second = ref.watch(eventParticipantsProvider('other')).asData?.value;
    final profile = ref.watch(
      publicProfileProvider((
        code: 'other-code',
        session: ref.watch(apiClientProvider).sessionVersion,
      )),
    );
    return SizedBox(
      height: 48,
      child: Text(
        [
          'following:${following?.length}',
          'members:${circles?.first.members.length}',
          'blocked:${blocked?.length}',
          'followers:${followers?.length}',
          'friends:${friendships?.length}',
          'friendStatus:${friendships?.firstOrNull?.status}',
          'sameWorks:${sameWorks?.items.length}',
          'eventFollow:${events?.first.followedDayIndexes.contains(2)}',
          'eventFriends:${events?.first.hasFriends}',
          'friendDays:${events?.first.friendDayIndexes.join(',')}',
          'first:${first?.length}:${first?.firstOrNull?.isFollowed}',
          'second:${second?.length}:${second?.firstOrNull?.isFollowed}',
          'profile:${profile.asData?.value?.isFollowed}',
        ].join(' '),
        key: const ValueKey('cached-views'),
        style: const TextStyle(fontSize: 12, height: 1.2),
        maxLines: 3,
        overflow: TextOverflow.clip,
      ),
    );
  }
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _filledButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

Finder get _introductionField => find.descendant(
  of: find.byType(FriendInviteDialog),
  matching: find.byType(TextFormField),
);

Future<void> _tapButton(WidgetTester tester, Finder button) async {
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Future<void> _openProfile(
  WidgetTester tester,
  _Relationships state, {
  bool unblockContract = false,
}) async {
  _setViewport(tester);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Column(
          children: [
            const _CachedViews(),
            if (unblockContract)
              Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    await ref.read(profileRepositoryProvider).unblockUser('2');
                    if (context.mounted) refreshFriendships(ref);
                  },
                  child: const Text('解除封鎖契約'),
                ),
              ),
            const Expanded(child: PublicProfilePage(publicCode: 'peer')),
          ],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Profile(state)),
        socialRepositoryProvider.overrideWithValue(_Social(state)),
        eventRepositoryProvider.overrideWithValue(_Events(state)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

String _cachedText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('cached-views'))).data!;

Future<void> _openInvite(
  WidgetTester tester,
  SocialRepository repository,
  Future<List<CosEvent>> Function() load, {
  bool preselected = false,
}) async {
  _setViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        socialRepositoryProvider.overrideWithValue(repository),
        eventsProvider.overrideWith((ref) => load()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => FriendInviteDialog(
                  userId: '2',
                  eventId: preselected ? '10' : null,
                  dayIndex: preselected ? 2 : null,
                ),
              ),
              child: const Text('邀請'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('邀請'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  // Flush the provider's completion without settling an intentional loader.
  await tester.pump();
  expect(find.byType(FriendInviteDialog), findsOneWidget);
  expect(_introductionField, findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'fixture'});
  });

  testWidgets('Q12 profile follow and unfollow refresh retained social views', (
    tester,
  ) async {
    final state = _Relationships();
    await _openProfile(tester, state);
    expect(_cachedText(tester), contains('following:0'));
    expect(_cachedText(tester), contains('eventFollow:false'));

    await _tapButton(tester, _filledButton('加入關注'));
    await tester.pumpAndSettle();
    for (final expected in [
      'following:1',
      'eventFollow:true',
      'first:1:true',
      'second:1:true',
      'profile:true',
    ]) {
      expect(_cachedText(tester), contains(expected));
    }

    await _tapButton(tester, _filledButton('取消關注'));
    await tester.pumpAndSettle();
    for (final expected in [
      'following:0',
      'eventFollow:false',
      'first:1:false',
      'second:1:false',
      'profile:false',
    ]) {
      expect(_cachedText(tester), contains(expected));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Q12 block refreshes blocked list and all visibility caches', (
    tester,
  ) async {
    final state = _Relationships()..followed = true;
    await _openProfile(tester, state);
    for (final expected in [
      'following:1',
      'members:1',
      'blocked:0',
      'followers:1',
      'friends:1',
      'sameWorks:1',
      'eventFriends:true',
    ]) {
      expect(_cachedText(tester), contains(expected));
    }
    await tester.ensureVisible(find.byTooltip('封鎖'));
    await tester.tap(find.byTooltip('封鎖'));
    await tester.pumpAndSettle();
    await _tapButton(tester, _filledButton('封鎖'));
    await tester.pumpAndSettle();
    for (final expected in [
      'following:0',
      'members:0',
      'blocked:1',
      'followers:0',
      'friends:0',
      'sameWorks:0',
      'eventFollow:false',
      'eventFriends:false',
      'first:0:null',
      'second:0:null',
      'profile:null',
    ]) {
      expect(_cachedText(tester), contains(expected));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Q12 common helper refreshes retained caches for unblock callers',
    (tester) async {
      final state = _Relationships()..blocked = true;
      await _openProfile(tester, state, unblockContract: true);
      expect(_cachedText(tester), contains('blocked:1'));
      expect(_cachedText(tester), contains('members:0'));
      expect(_cachedText(tester), contains('first:0:null'));
      await tester.tap(find.text('解除封鎖契約'));
      await tester.pumpAndSettle();
      for (final expected in [
        'following:0',
        'members:1',
        'blocked:0',
        'followers:1',
        'friends:1',
        'sameWorks:1',
        'eventFollow:false',
        'eventFriends:true',
        'first:1:false',
        'second:1:false',
        'profile:false',
      ]) {
        expect(_cachedText(tester), contains(expected));
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['follow', 'unfollow', 'block']) {
    testWidgets('Q12 failed $action preserves cached relationship state', (
      tester,
    ) async {
      final state = _Relationships()
        ..followed = action == 'unfollow'
        ..fail = true;
      await _openProfile(tester, state);
      final before = _cachedText(tester);
      if (action == 'block') {
        await tester.ensureVisible(find.byTooltip('封鎖'));
        await tester.tap(find.byTooltip('封鎖'));
        await tester.pumpAndSettle();
        await _tapButton(tester, _filledButton('封鎖'));
      } else {
        final button = _filledButton(action == 'follow' ? '加入關注' : '取消關注');
        await _tapButton(tester, button);
      }
      await tester.pumpAndSettle();
      expect(_cachedText(tester), before);
      expect(find.text(action == 'block' ? '封鎖失敗' : '關注失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['accept', 'ignore', 'remove']) {
    for (final fail in [false, true]) {
      testWidgets('Q12 $action ${fail ? 'failure preserves' : 'refreshes'} '
          'retained friendship and event views', (tester) async {
        final state = _Relationships()
          ..friendshipStatus = action == 'remove' ? 'accepted' : 'incoming'
          ..fail = fail;
        await _openProfile(tester, state);
        final before = _cachedText(tester);
        if (action == 'remove') {
          await tester.ensureVisible(find.byTooltip('解除戳友'));
          await tester.tap(find.byTooltip('解除戳友'));
          await tester.pumpAndSettle();
          await _tapButton(tester, _filledButton('解除'));
        } else {
          final button = find.text(action == 'accept' ? '確認戳友' : '忽略');
          await tester.ensureVisible(button);
          await tester.tap(button);
        }
        await tester.pumpAndSettle();
        if (fail) {
          expect(_cachedText(tester), before);
          expect(find.text('社交操作失敗'), findsOneWidget);
          expect(state.responses, isEmpty);
          expect(state.removals, isEmpty);
        } else {
          final accepted = action == 'accept';
          for (final expected in [
            'friends:${accepted ? 1 : 0}',
            'friendStatus:${accepted ? 'accepted' : 'null'}',
            'eventFriends:$accepted',
            'friendDays:${accepted ? '2' : ''}',
          ]) {
            expect(_cachedText(tester).split(' '), contains(expected));
          }
          expect(state.responses, action == 'remove' ? [] : [accepted]);
          expect(state.removals, action == 'remove' ? ['2'] : []);
          if (!accepted) expect(find.text('戳友'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final fail in [false, true]) {
    testWidgets('Q12 invitation ${fail ? 'failure preserves' : 'refreshes'} '
        'retained profile friendship state', (tester) async {
      final state = _Relationships()
        ..friendshipStatus = null
        ..fail = fail;
      await _openProfile(tester, state);
      final before = _cachedText(tester);
      await tester.ensureVisible(find.text('戳友'));
      await tester.tap(find.text('戳友'));
      await tester.pumpAndSettle();
      await tester.enterText(_introductionField, friends.intro);
      await tester.tap(find.text('送出邀請'));
      await tester.pumpAndSettle();
      if (fail) {
        expect(_cachedText(tester), before);
        expect(state.invitations, isEmpty);
        expect(find.text('社交操作失敗'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester.widget<TextFormField>(_introductionField).controller!.text,
          friends.intro,
        );
        state.fail = false;
        await tester.tap(find.text('送出邀請'));
        await tester.pumpAndSettle();
        expect(state.invitations, [
          {
            'userId': '2',
            'introduction': friends.intro,
            'eventId': null,
            'dayIndex': null,
          },
        ]);
        expect(_cachedText(tester), contains('friendStatus:pending'));
        expect(find.text('等待確認'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(state.invitations, [
          {
            'userId': '2',
            'introduction': friends.intro,
            'eventId': null,
            'dayIndex': null,
          },
        ]);
        expect(_cachedText(tester), contains('friends:1'));
        expect(_cachedText(tester), contains('friendStatus:pending'));
        expect(find.text('等待確認'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final loading in [false, true]) {
    testWidgets('Q15 eventless invite works while events are '
        '${loading ? 'loading' : 'failed'}', (tester) async {
      final pending = Completer<List<CosEvent>>();
      final repository = friends.FriendRepository();
      await _openInvite(
        tester,
        repository,
        () => loading ? pending.future : Future.error(Exception('場次失敗')),
      );
      expect(find.text('未指定場次'), findsOneWidget);
      if (!loading) {
        expect(find.text('場次載入失敗，重試'), findsOneWidget);
      } else {
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      }
      await tester.tap(find.text('送出邀請'));
      await tester.pump();
      expect(find.text('請留下方便辨認的介紹'), findsOneWidget);
      expect(repository.invitations, isEmpty);
      await tester.enterText(_introductionField, friends.intro);
      await tester.tap(find.text('送出邀請'));
      await tester.pumpAndSettle();
      expect(repository.invitations, [
        {
          'userId': '2',
          'introduction': friends.intro,
          'eventId': null,
          'dayIndex': null,
        },
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      pending.complete([]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Q15 failed send preserves note and D2 selection for retry', (
    tester,
  ) async {
    final state = _Relationships()
      ..friendshipStatus = null
      ..fail = true;
    await _openInvite(
      tester,
      _Social(state),
      () async => [friends.event],
      preselected: true,
    );
    await tester.enterText(_introductionField, '  ${friends.intro}  ');
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(find.text('社交操作失敗'), findsOneWidget);
    expect(find.byType(FriendInviteDialog), findsOneWidget);
    expect(state.invitations, isEmpty);
    expect(
      tester.widget<TextFormField>(_introductionField).controller!.text,
      '  ${friends.intro}  ',
    );
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      '10:2',
    );
    expect(
      tester.widget<FilledButton>(_filledButton('送出邀請')).onPressed,
      isNotNull,
    );
    state.fail = false;
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(state.invitations, [
      {
        'userId': '2',
        'introduction': friends.intro,
        'eventId': '10',
        'dayIndex': 2,
      },
    ]);
    expect(find.byType(FriendInviteDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Q15 optional picker retry preserves note and exact day', (
    tester,
  ) async {
    var attempts = 0;
    final repository = friends.FriendRepository();
    await _openInvite(tester, repository, () async {
      if (++attempts == 1) throw Exception('場次失敗');
      return [friends.event];
    }, preselected: true);
    await tester.enterText(_introductionField, friends.intro);
    expect(
      tester.widget<FilledButton>(_filledButton('送出邀請')).onPressed,
      isNull,
    );
    await tester.tap(find.text('場次載入失敗，重試'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('場次載入失敗，重試'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      friends.intro,
    );
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(repository.invitations.single['eventId'], '10');
    expect(repository.invitations.single['dayIndex'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Q15 failed preselected picker can explicitly become eventless', (
    tester,
  ) async {
    final repository = friends.FriendRepository();
    await _openInvite(
      tester,
      repository,
      () async => throw Exception('場次失敗'),
      preselected: true,
    );
    await tester.enterText(_introductionField, friends.intro);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未指定場次').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(repository.invitations.single['eventId'], isNull);
    expect(repository.invitations.single['dayIndex'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Q15 optional picker can retry and select a day from eventless', (
    tester,
  ) async {
    var attempts = 0;
    final repository = friends.FriendRepository();
    await _openInvite(tester, repository, () async {
      if (++attempts == 1) throw Exception('場次失敗');
      return [friends.event];
    });
    await tester.enterText(_introductionField, friends.intro);
    await tester.tap(find.text('場次載入失敗，重試'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2026/10/10').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(repository.invitations, [
      {
        'userId': '2',
        'introduction': friends.intro,
        'eventId': '10',
        'dayIndex': 2,
      },
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Q15 missing preselected day must not silently send eventless', (
    tester,
  ) async {
    final repository = friends.FriendRepository();
    await _openInvite(tester, repository, () async => [], preselected: true);
    await tester.enterText(_introductionField, friends.intro);
    expect(find.text('已選場次（已無法選取）'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_filledButton('送出邀請')).onPressed,
      isNull,
    );
    expect(repository.invitations, isEmpty);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未指定場次').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(repository.invitations.single['eventId'], isNull);
    expect(repository.invitations.single['dayIndex'], isNull);
    expect(tester.takeException(), isNull);
  });
}
