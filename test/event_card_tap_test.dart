import 'package:coscircle/core/models/event.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/features/events/presentation/widgets/event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  for (final status in EventStatus.values) {
    testWidgets('$status card opens details while booking stays independent', (
      tester,
    ) async {
      var details = 0;
      var bookings = 0;
      final date = DateTime(2026, 10, 14);
      final event = CosEvent(
        id: 'card',
        name: '測試活動',
        category: '同人',
        startDate: date,
        endDate: date,
        venue: '測試場地',
        detailedAddress: '',
        fee: '',
        organizer: '',
        description: '',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWithValue(
              InMemoryEventRepository(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EventCard(
                event: event,
                statusOverride: status,
                onDetailPressed: () => details++,
                onBookingPressed: () => bookings++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('測試活動'));
      await tester.pumpAndSettle();
      expect(details, 1);
      await tester.tap(find.text('測試場地'));
      await tester.pumpAndSettle();
      expect(details, 2);
      await tester.tap(find.text('詳細'));
      await tester.pumpAndSettle();
      expect(details, 3);
      final bookingFinder = find.byWidgetPredicate(
        (widget) => widget is FilledButton,
      );
      final booking = tester.widget<FilledButton>(bookingFinder);
      if (status == EventStatus.ended) {
        expect(booking.onPressed, isNull);
      } else {
        await tester.tap(bookingFinder);
        await tester.pumpAndSettle();
        expect(bookings, 1);
        expect(details, 3);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
