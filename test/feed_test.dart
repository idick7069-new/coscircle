import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/feed_post.dart';
import 'package:coscircle/core/repositories/feed_repository.dart';
import 'package:coscircle/features/feed/presentation/feed_page.dart';

class FixtureFeed extends FeedRepository {
  FixtureFeed() : super(ApiClient(baseUrl: 'https://example.invalid/api'));
  String? requestedKind, requestedScope;
  int likes = 0;
  @override
  Future<FeedResult> list({
    String kind = 'all',
    String scope = 'all',
    String? eventId,
    String? before,
  }) async {
    requestedKind = kind;
    requestedScope = scope;
    return FeedResult.fromJson({
      'items': [
        {
          'id': '1',
          'authorId': '3',
          'nickname': '同坑夥伴',
          'publicCode': 'test',
          'kind': 'booking',
          'body': '週末見！',
          'visibility': 'public',
          'eventId': '10',
          'eventName': '同人活動',
          'eventDate': '2027-01-01',
          'dayIndex': 2,
          'cancelled': true,
          'sameWork': true,
          'workName': '原神',
          'commentsEnabled': true,
          'likeCount': likes,
          'commentCount': 0,
          'liked': likes > 0,
        },
      ],
      'nextCursor': null,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> notifications() async => [];
  @override
  Future<void> like(String id, bool enabled) async {
    likes = enabled ? 1 : 0;
  }
}

void main() {
  test(
    'feed model preserves cancellation, circle scope and canonical edit fields',
    () {
      final p = FeedPost({
        'id': 1,
        'authorId': 2,
        'kind': 'booking',
        'cancelled': 1,
        'commentsEnabled': false,
        'visibility': 'circle',
        'circleId': '5',
        'images': ['https://coscircle.app/uploads/a.png'],
      });
      expect(p.id, '1');
      expect(p.cancelled, true);
      expect(p.commentsEnabled, false);
      expect(p.toEditJson()['visibility'], 'circle');
      expect(p.toEditJson()['circleId'], '5');
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'feed shows cancelled booking, same-work signal, filters and working like at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FixtureFeed();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [feedRepositoryProvider.overrideWithValue(repo)],
            child: const MaterialApp(home: Scaffold(body: FeedPage())),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('已取消預定'), findsOneWidget);
        expect(find.text('跟你同坑 · 原神'), findsOneWidget);
        expect(find.text('分享預定'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byIcon(Icons.favorite_border));
        await tester.tap(find.byIcon(Icons.favorite_border));
        await tester.pumpAndSettle();
        expect(repo.likes, 1);
        await tester.tap(find.text('看看大家'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('與我同坑').last);
        await tester.pumpAndSettle();
        expect(repo.requestedScope, 'same-work');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
