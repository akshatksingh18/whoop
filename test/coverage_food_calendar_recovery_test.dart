// Authored local food only. Calendar read failures must not imply an empty log.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_calendar.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-06';
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Finder control(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-calendar-recovery');
  });
  setUp(() async {
    await resetCoverageStore();
    final db = await LocalDb.instance;
    for (final (date, id) in [(day, 'counted'), ('2021-04-07', 'unknown')]) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: id,
          date: date,
          meal: 'lunch',
          label: 'Synthetic $id',
          kcal: id == 'counted' ? 400 : null,
        ),
      );
    }
    await NutritionDb.setDayMark(db, day, 'complete');
  });
  tearDownAll(LocalDb.close);

  testWidgets(
    'month dialog reads saved marks, changes month and returns the chosen historical date',
    (t) async {
      String? chosen;
      await localizedPage(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              chosen = await showFoodCalendar(c, day);
            },
            child: const Text('Choose authored day'),
          ),
        ),
      );
      await t.tap(find.text('Choose authored day'));
      await flush(t);
      expect(find.text('April 2021'), findsOneWidget);
      final marks = await t.runAsync(() => loadFoodMarks(day, day));
      expect(marks![day], FoodDayMark.counted);
      expect(marks['2021-04-07'], FoodDayMark.logged);
      expect(marks['2021-04-08'], FoodDayMark.empty);
      await t.tap(find.byTooltip('Previous month'));
      await flush(t);
      expect(find.text('March 2021'), findsOneWidget);
      await t.tap(find.byTooltip('Next month'));
      await flush(t);
      expect(find.text('April 2021'), findsOneWidget);
      await t.tap(control(dayTitle('2021-04-07')));
      await flush(t);
      expect(find.byType(FoodCalendar), findsNothing);
      expect(chosen, '2021-04-07');
      expect(
        await t.runAsync(
          () async => NutritionDb.entriesForDay(await LocalDb.instance, day),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'failed month exposes Retry and rereads saved marks after storage returns',
    (t) async {
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE food_entry RENAME TO synthetic_hidden_food_entry',
      );
      var hidden = true;
      try {
        await localizedPage(t, const FoodCalendar(current: day));
        await flush(t);
        expect(control('Day marks could not load. Retry'), findsOneWidget);
        // No per-day dot can claim "Nothing logged" before the month was read.
        int dots() => find
            .byWidgetPredicate((w) => w.runtimeType.toString() == '_MarkDot')
            .evaluate()
            .length;
        expect(
          dots(),
          3,
          reason: 'Only the three explanatory legend dots remain',
        );
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE synthetic_hidden_food_entry RENAME TO food_entry',
          ),
        );
        hidden = false;
        await t.tap(control('Day marks could not load. Retry'));
        await flush(t);
        expect(control('Day marks could not load. Retry'), findsNothing);
        expect(
          dots(),
          33,
          reason: 'All 30 past days plus the legend are now known',
        );
        expect(
          (await t.runAsync(() => loadFoodMarks(day, day)))![day],
          FoodDayMark.counted,
        );
      } finally {
        if (hidden) {
          await t.runAsync(
            () => db.execute(
              'ALTER TABLE synthetic_hidden_food_entry RENAME TO food_entry',
            ),
          );
        }
      }
    },
  );

  testWidgets(
    'an unreadable week still navigates without declaring days empty then recovers on revision',
    (t) async {
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE food_entry RENAME TO synthetic_hidden_food_entry',
      );
      var hidden = true;
      String? chosen;
      try {
        await localizedPage(
          t,
          FoodWeekStrip(date: day, onDay: (d) => chosen = d),
        );
        await flush(t);
        expect(control(dayTitle(day)), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Pressable &&
                (w.semanticLabel?.contains('nothing logged') ?? false),
          ),
          findsNothing,
        );
        await t.tap(control(dayTitle(day)));
        expect(chosen, day);
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE synthetic_hidden_food_entry RENAME TO food_entry',
          ),
        );
        hidden = false;
        NutritionDb.changed();
        await flush(t);
        expect(control('${dayTitle(day)}, counted'), findsOneWidget);
        expect(
          control('${dayTitle('2021-04-07')}, food logged, not counted'),
          findsOneWidget,
        );
        expect(
          control('${dayTitle('2021-04-08')}, nothing logged'),
          findsOneWidget,
        );
      } finally {
        if (hidden) {
          await t.runAsync(
            () => db.execute(
              'ALTER TABLE synthetic_hidden_food_entry RENAME TO food_entry',
            ),
          );
        }
      }
    },
  );

  testWidgets(
    'date picker permits the viewed older year and sends the confirmed day back',
    (t) async {
      String? chosen;
      await localizedPage(t, DayHeader(day, (d) => chosen = d));
      await t.tap(control('Choose a day, ${dayTitle(day)}'));
      await t.pumpAndSettle();
      final picker = t.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.firstDate, DateTime(2021, 4, 6));
      picker.onDateChanged(DateTime(2021, 4, 8));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await flush(t);
      expect(chosen, '2021-04-08');
    },
  );
}
