import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/circle.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/repositories/feed_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/repositories/social_repository.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/features/feed/presentation/feed_composer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Feed extends FeedRepository {
  _Feed() : super(ApiClient(baseUrl: 'https://example.invalid/api'));
  Map<String, dynamic>? saved;
  @override
  Future<String> save(Map<String, dynamic> body, {String? id}) async {
    saved = body;
    return '100';
  }
}

class _Social extends SocialRepository {
  _Social()
    : super(apiClient: ApiClient(baseUrl: 'https://example.invalid/api'));
  @override
  Future<List<CircleGroup>> fetchCircles() async => [
    const CircleGroup(
      id: '5',
      name: '同坑圈',
      inviteCode: 'qa',
      inviteUrl: 'https://example.invalid',
      memberCount: 2,
      isOwner: false,
    ),
  ];
}

class _Profile extends InMemoryProfileRepository {
  @override
  Future<UserProfile?> currentProfile() async =>
      const UserProfile(id: '1', nickname: 'QA');
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'composer requires content and offers circle scope, keeps publish button reachable at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final feed = _Feed();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              feedRepositoryProvider.overrideWithValue(feed),
              socialRepositoryProvider.overrideWithValue(_Social()),
              profileRepositoryProvider.overrideWithValue(_Profile()),
              eventRepositoryProvider.overrideWithValue(
                InMemoryEventRepository(),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FeedComposerPage(),
                      ),
                    ),
                    child: const Text('開始發文'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('開始發文'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final publish = find.text('發佈');
        await tester.ensureVisible(publish);
        await tester.tap(publish);
        await tester.pumpAndSettle();
        expect(feed.saved, isNull);
        expect(find.text('寫一些內容或加入照片吧'), findsOneWidget);
        final body = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '想分享什麼？',
        );
        await tester.ensureVisible(body);
        await tester.enterText(body, '下一場想找同坑夥伴拍照！');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.getRect(publish).bottom, lessThanOrEqualTo(550));
        await tester.tap(publish);
        await tester.pumpAndSettle();
        expect(feed.saved?['body'], '下一場想找同坑夥伴拍照！');
        expect(feed.saved?['visibility'], 'public');
        expect(find.text('開始發文'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
