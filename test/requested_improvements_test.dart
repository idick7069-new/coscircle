import 'dart:async';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/models/participant.dart';
import 'package:coscircle/core/models/work.dart';
import 'package:coscircle/core/providers/event_providers.dart';
import 'package:coscircle/features/events/presentation/same_work_coser_notice.dart';
import 'package:coscircle/features/events/presentation/event_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';

const people = [
  EventParticipant(
    userId: 'me',
    nickname: 'Me',
    role: 'coser',
    workId: 'a',
    dayIndex: 1,
    isMe: true,
  ),
  EventParticipant(
    userId: '1',
    nickname: 'A',
    role: 'coser',
    workId: 'a',
    dayIndex: 1,
  ),
  EventParticipant(
    userId: '1',
    nickname: 'A duplicate',
    role: 'coser',
    workId: 'a',
    dayIndex: 1,
  ),
  EventParticipant(
    userId: '2',
    nickname: 'B',
    role: 'coser',
    workId: 'a',
    dayIndex: 2,
  ),
  EventParticipant(
    userId: '3',
    nickname: 'Photo',
    role: 'photographer',
    workId: 'a',
    dayIndex: 1,
  ),
  EventParticipant(
    userId: '4',
    nickname: 'Other work',
    role: 'coser',
    workId: 'b',
    dayIndex: 1,
  ),
];
void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'private age round-trips, survives unrelated edits, and stays out of labels',
    () {
      final p = UserProfile.fromJson({
        'id': '1',
        'nickname': 'QA',
        'age': '24',
        'agePublic': false,
      });
      expect(p.ageLabel, '不公開');
      expect(p.copyWith(nickname: 'Other').toJson()['agePublic'], false);
      expect(p.copyWith(agePublic: true).age, '24');
      expect(p.copyWith(agePublic: true).ageLabel, '24');
      expect(
        UserProfile.fromJson({
          'id': '2',
          'nickname': 'Old',
          'age': '24',
        }).agePublic,
        true,
      );
    },
  );
  test('same-work count is per-day, unique, Coser-only and excludes self', () {
    expect(matchingCoserCount(people, dayIndex: 1, workId: 'a'), 1);
    expect(matchingCoserCount(people, dayIndex: 2, workId: 'a'), 1);
    expect(matchingCoserCount(people, dayIndex: 1, workId: 'b'), 1);
    expect(matchingCoserCount(people, dayIndex: 1, workId: ''), 0);
    expect(matchingCoserCount(people, dayIndex: 3, workId: 'a'), 0);
  });
  testWidgets(
    'selected work and day update the visible count without a second fetch',
    (tester) async {
      int requests = 0;
      Widget host(String work, int day) => ProviderScope(
        overrides: [
          eventParticipantsProvider('qa').overrideWith((ref) async {
            requests++;
            return people;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SameWorkCoserNotice(
              eventId: 'qa',
              dayIndex: day,
              work: WorkTag(id: work, name: work),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host('a', 1));
      await tester.pumpAndSettle();
      expect(find.text('已有 1 位 Coser 也要出「a」'), findsOneWidget);
      await tester.pumpWidget(host('b', 1));
      await tester.pumpAndSettle();
      expect(find.text('已有 1 位 Coser 也要出「b」'), findsOneWidget);
      await tester.pumpWidget(host('b', 2));
      await tester.pumpAndSettle();
      expect(find.text('目前還沒有其他 Coser 預訂這部作品'), findsOneWidget);
      expect(requests, 1);
    },
  );
  testWidgets(
    'pending and failed participant requests never claim zero Cosers',
    (tester) async {
      final pending = Completer<List<EventParticipant>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventParticipantsProvider(
              'qa',
            ).overrideWith((ref) => pending.future),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SameWorkCoserNotice(
                eventId: 'qa',
                dayIndex: 1,
                work: WorkTag(id: 'a', name: 'A'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('正在確認同作品 Coser…'), findsOneWidget);
      expect(find.textContaining('還沒有其他'), findsNothing);
      pending.completeError(Exception('offline'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('同作品人數暫時無法取得'), findsOneWidget);
      expect(find.textContaining('還沒有其他'), findsNothing);
    },
  );
  testWidgets(
    'today overrides a previously saved date and is selected on tab re-entry',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'event_list_selected_day': '2020-01-01',
        'event_list_focused_day': '2020-01-01',
      });
      Widget host(bool visible) => ProviderScope(
        overrides: [eventsProvider.overrideWith((ref) async => [])],
        child: MaterialApp(
          home: Scaffold(
            body: EventListPage(isVisible: visible, onOpenCurrentEvent: (_) {}),
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      TableCalendar calendar() => tester.widget<TableCalendar>(
        find.byWidgetPredicate((w) => w is TableCalendar),
      );
      expect(calendar().selectedDayPredicate!(DateTime.now()), true);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      calendar().onDaySelected!(tomorrow, tomorrow);
      await tester.pumpAndSettle();
      expect(calendar().selectedDayPredicate!(tomorrow), true);
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      expect(calendar().selectedDayPredicate!(DateTime.now()), true);
    },
  );
}
