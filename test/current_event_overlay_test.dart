import 'package:coscircle/core/models/meetup_point.dart';
import 'package:coscircle/core/models/recognition_request.dart';
import 'package:coscircle/features/current_event/presentation/widgets/current_event_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('集合通知顯示小圈圈、地點並可點導航', (tester) async {
    var navigated = false;
    final meetup = MeetupPoint(
      id: '1',
      eventId: '2',
      circleId: '3',
      circleName: '北門拍照小圈圈',
      creatorUserId: '1',
      creatorNickname: '圈圈新朋友',
      latitude: 25.033,
      longitude: 121.565,
      description: '大門口左邊樹下',
      meetAt: DateTime(2026, 6, 2, 14, 30),
      createdAt: DateTime(2026, 6, 2, 13),
      isMine: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeetupNoticeCard(
            meetup: meetup,
            onNavigate: () => navigated = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('北門拍照小圈圈'), findsOneWidget);
    expect(find.text('大門口左邊樹下'), findsOneWidget);

    await tester.tap(find.text('導航'));
    expect(navigated, isTrue);
  });

  testWidgets('認親通知可回覆快來或當前不方便', (tester) async {
    var came = false;
    var busy = false;
    final request = RecognitionRequest(
      id: '9',
      eventId: '2',
      requesterUserId: '8',
      requesterNickname: '阿月',
      targetUserId: '1',
      targetNickname: '圈圈新朋友',
      status: RecognitionStatus.pending,
      createdAt: DateTime(2026, 6, 2, 13),
      isTarget: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecognitionNoticeCard(
            request: request,
            onCome: () => came = true,
            onBusy: () => busy = true,
          ),
        ),
      ),
    );

    expect(find.text('阿月 要過來認親'), findsOneWidget);

    await tester.tap(find.text('快來'));
    expect(came, isTrue);

    await tester.tap(find.text('當前不方便'));
    expect(busy, isTrue);
  });
}
