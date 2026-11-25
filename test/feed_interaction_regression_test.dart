import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/models/feed_post.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/models/circle.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/core/repositories/feed_repository.dart';
import 'package:coscircle/features/feed/presentation/feed_page.dart';
import 'package:coscircle/features/feed/presentation/feed_composer_page.dart';

FeedPost post({
  bool mine = true,
  int likes = 0,
  int comments = 0,
  bool open = true,
}) => FeedPost({
  'id': '10',
  'authorId': '1',
  'publicCode': 'author',
  'nickname': '作者',
  'body': 'QA 動態',
  'kind': 'general',
  'visibility': 'public',
  'isMe': mine,
  'commentsEnabled': open,
  'likeCount': likes,
  'commentCount': comments,
  'images': [],
});

class _Feed extends FeedRepository {
  _Feed() : super(ApiClient(baseUrl: 'https://example.invalid/api'));
  int listCalls = 0, saveCalls = 0, likeCalls = 0, commentCalls = 0;
  bool failRefresh = false,
      failShare = false,
      failLike = false,
      failSave = false,
      failComment = false;
  bool liked = false;
  FeedPost item = post();
  Completer<Map<String, dynamic>?>? pendingShare;
  Completer<void>? pendingComment;
  Map<String, dynamic>? saved;
  final rows = <Map<String, dynamic>>[];
  @override
  Future<FeedResult> list({
    String kind = 'all',
    String scope = 'all',
    String? eventId,
    String? before,
  }) async {
    listCalls++;
    if (failRefresh) {
      failRefresh = false;
      throw Exception('測試斷線');
    }
    return FeedResult.fromJson({
      'items': [item.data],
      'nextCursor': null,
    });
  }

  @override
  Future<FeedPost> detail(String id) async =>
      FeedPost({...item.data, 'liked': liked, 'likeCount': liked ? 1 : 0});
  @override
  Future<List<Map<String, dynamic>>> notifications() async => [];
  @override
  Future<String> save(Map<String, dynamic> body, {String? id}) async {
    saveCalls++;
    if (failSave) {
      failSave = false;
      throw Exception('測試儲存失敗');
    }
    saved = body;
    item = FeedPost({...item.data, ...body});
    return '10';
  }

  @override
  Future<Map<String, dynamic>?> bookingShare(
    String eventId,
    int dayIndex,
  ) async {
    if (failShare) throw Exception('測試分享設定斷線');
    if (pendingShare != null) return pendingShare!.future;
    return dayIndex == 1
        ? {
            'id': '10',
            'body': 'D1 私人文字',
            'visibility': 'circle',
            'circleId': '5',
          }
        : null;
  }

  @override
  Future<void> like(String id, bool enabled) async {
    likeCalls++;
    if (failLike) {
      failLike = false;
      throw Exception('測試按讚失敗');
    }
    liked = enabled;
  }

  @override
  Future<Map<String, dynamic>> comments(String id, {String? before}) async => {
    'items': [...rows],
    'nextCursor': null,
  };
  @override
  Future<void> comment(String id, String body, {String? parentId}) async {
    commentCalls++;
    if (failComment) {
      failComment = false;
      throw Exception('測試留言失敗');
    }
    if (pendingComment != null) await pendingComment!.future;
    rows.insert(0, {
      'id': '$commentCalls',
      'authorId': '1',
      'publicCode': 'author',
      'nickname': '作者',
      'body': body,
      'isMe': true,
      'parentId': parentId,
    });
  }
}

class _Profile extends InMemoryProfileRepository {
  Completer<UserProfile?>? pending;
  @override
  Future<UserProfile?> currentProfile() async => pending == null
      ? const UserProfile(id: '1', nickname: '作者')
      : pending!.future;
}

class _Social extends SocialRepository {
  _Social()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  @override
  Future<List<CircleGroup>> fetchCircles() async => [
    const CircleGroup(
      id: '5',
      name: 'QA 小圈圈',
      inviteCode: 'fixture',
      inviteUrl: 'https://example.invalid',
      memberCount: 2,
      isOwner: true,
    ),
  ];
}

class _Events extends InMemoryEventRepository {
  @override
  Future<List<CosEvent>> fetchEvents() async => [
    CosEvent(
      id: '20',
      name: 'QA 場次',
      category: 'QA',
      startDate: DateTime(2027),
      endDate: DateTime(2027, 1, 3),
      venue: 'QA',
      detailedAddress: '',
      fee: '',
      organizer: '',
      description: '',
    ),
  ];
  @override
  Future<Map<String, List<EventParticipant>>> fetchMyBookings() async => {
    '20': [
      const EventParticipant(
        userId: '1',
        nickname: '作者',
        role: 'coser',
        dayIndex: 1,
        isMe: true,
      ),
      const EventParticipant(
        userId: '1',
        nickname: '作者',
        role: 'coser',
        dayIndex: 2,
        isMe: true,
      ),
    ],
  };
}

Future<void> _open(
  WidgetTester tester,
  _Feed repo,
  Widget child, {
  _Profile? profile,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(repo),
        profileRepositoryProvider.overrideWithValue(profile ?? _Profile()),
        eventRepositoryProvider.overrideWithValue(_Events()),
        socialRepositoryProvider.overrideWithValue(_Social()),
      ],
      child: MaterialApp(
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder textField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Finder send() =>
    find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '送出留言');
void main() {
  testWidgets(
    'refresh failure at end of feed can retry instead of silently doing nothing',
    (tester) async {
      final repo = _Feed();
      await _open(tester, repo, const FeedPage());
      expect(repo.listCalls, 1);
      repo.failRefresh = true;
      await tester.tap(find.byTooltip('重新整理動態'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重試'));
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(repo.listCalls, 3);
      expect(find.text('測試斷線'), findsNothing);
    },
  );
  testWidgets(
    'switching booking days clears the other days text and private audience',
    (tester) async {
      final repo = _Feed();
      await _open(tester, repo, const FeedComposerPage(booking: true));
      expect(find.text('D1 私人文字'), findsOneWidget);
      await tester.tap(find.text('QA 場次 · D1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('QA 場次 · D2').last);
      await tester.pumpAndSettle();
      final field = textField('跟同好說幾句（選填）');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      final audience = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == '誰可以看到',
      );
      expect(
        find.descendant(of: audience, matching: find.text('公開')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'booking lookup failure must be recoverable and cannot publish over unknown sharing settings',
    (tester) async {
      final repo = _Feed()..failShare = true;
      await _open(tester, repo, const FeedComposerPage(booking: true));
      await tester.tap(find.text('發佈'));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 0);
      repo.failShare = false;
      expect(find.text('重新載入分享設定'), findsOneWidget);
      await tester.ensureVisible(find.text('重新載入分享設定'));
      await tester.tap(find.text('重新載入分享設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('發佈'));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 1);
      expect(repo.saved?['visibility'], 'circle');
    },
  );
  testWidgets(
    'own post controls do not wait for an unrelated profile request',
    (tester) async {
      final repo = _Feed();
      final profile = _Profile()..pending = Completer<UserProfile?>();
      await _open(tester, repo, FeedPostCard(post: post()), profile: profile);
      await tester.tap(find.byTooltip('貼文選項'));
      await tester.pumpAndSettle();
      expect(find.text('編輯貼文'), findsOneWidget);
      expect(find.text('關閉留言'), findsOneWidget);
      expect(find.text('刪除貼文'), findsOneWidget);
      profile.pending!.complete(const UserProfile(id: '1', nickname: '作者'));
    },
  );
  testWidgets(
    'high interaction counts stay operable at 320px with enlarged text',
    (tester) async {
      final repo = _Feed();
      await _open(
        tester,
        repo,
        FeedPostCard(post: post(likes: 1234, comments: 1234, open: false)),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed like becomes clickable again and succeeds on retry', (
    tester,
  ) async {
    final repo = _Feed()..failLike = true;
    await _open(tester, repo, FeedPostCard(post: post()));
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    expect(repo.likeCalls, 2);
    expect(repo.liked, true);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'author comments and replies are marked for every viewer, not other users own comments',
    (tester) async {
      final repo = _Feed()..item = post(mine: false);
      repo.rows.addAll([
        {
          'id': '1',
          'authorId': '1',
          'nickname': '原作者',
          'body': '作者留言',
          'isMe': false,
        },
        {
          'id': '2',
          'authorId': 1,
          'nickname': '原作者',
          'body': '作者回覆',
          'parentId': '3',
          'isMe': false,
        },
        {
          'id': '3',
          'authorId': '2',
          'nickname': '其他同好',
          'body': '讀者留言',
          'isMe': true,
        },
      ]);
      await _open(tester, repo, const FeedDetailPage(postId: '10'), scale: 2);
      final authorBadge = find.byTooltip('貼文作者（原 PO）');
      expect(authorBadge, findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.text('其他同好'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('其他同好'), findsOneWidget);
      final other = find.ancestor(
        of: find.text('其他同好'),
        matching: find.byType(ListTile),
      );
      expect(find.descendant(of: other, matching: authorBadge), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty comment is disabled and failed comment retains text for retry',
    (tester) async {
      final repo = _Feed()..failComment = true;
      await _open(tester, repo, const FeedDetailPage(postId: '10'));
      expect(tester.widget<IconButton>(send()).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '可以一起拍照嗎？');
      await tester.pump();
      expect(tester.widget<IconButton>(send()).onPressed, isNotNull);
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '可以一起拍照嗎？',
      );
      expect(tester.widget<IconButton>(send()).onPressed, isNotNull);
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(repo.commentCalls, 2);
      expect(find.text('可以一起拍照嗎？'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
}
