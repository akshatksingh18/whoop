// Retained developer examples accept gestures while holding their authored state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/activity/workout_context.dart';
import 'package:whoop_companion/ui2/profile/gallery.dart';
import 'package:whoop_companion/ui2/screens/food_calendar.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart'
    show dayTitle, LogFoodScreen;
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Pressable && widget.semanticLabel == label,
);

Finder within(Finder area, Finder target) =>
    find.descendant(of: area, matching: target);

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('gallery-preview-action-safety');
  });
  setUp(() async {
    await resetCoverageStore();
    await JournalStore.put(
      '2021-04-06',
      '["travel"]',
      'Retained authored note',
    );
    await NutritionDb.put(
      await LocalDb.instance,
      const FoodEntry(
        id: 'gallery-synthetic-meal',
        date: '2021-04-06',
        meal: 'lunch',
        label: 'Retained authored meal',
        kcal: 240,
      ),
    );
  });
  tearDownAll(LocalDb.close);

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final db = await LocalDb.instance;
    return {
      for (final t in ['journal', 'journal_metric', 'food_entry', 'sessions'])
        t: await db.query(t),
    };
  }

  Future<void> examples(
    WidgetTester t,
    List<String> names,
    Future<void> Function() interact,
  ) async {
    final cases = galleryCases();
    final before = await snapshot();
    await localizedPage(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final name in names) cases[name]!],
          ),
        ),
      ),
    );
    await interact();
    expect(find.byType(LogFoodScreen), findsNothing);
    expect(find.byType(JournalCompose), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(await t.runAsync(snapshot), before);
    expect(t.takeException(), isNull);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    expect(f, findsOneWidget);
    await reveal(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'gallery tabs and oldest-day arrows keep their selected fixtures',
    (t) => examples(
      t,
      ['sub_tabs', 'sub_tabs_five', 'day_nav_oldest'],
      () async {
        final tabs = find.byType(SubTabs);
        for (final (index, label) in [(0, 'Strain'), (1, '30 days')]) {
          final before = t.widget<SubTabs>(tabs.at(index)).index;
          await tap(t, within(tabs.at(index), find.text(label)));
          expect(t.widget<SubTabs>(tabs.at(index)).index, before);
        }

        final calendar = find.byType(DayNav);
        final day = t.widget<DayNav>(calendar).day;
        expect(
          t.widget<Pressable>(within(calendar, control('Previous day'))).onTap,
          isNull,
        );
        await tap(t, within(calendar, control('Next day')));
        expect(t.widget<DayNav>(calendar).day, day);
      },
    ),
  );

  testWidgets(
    'gallery Food date and add examples cannot write to the real diary',
    (t) => examples(
      t,
      ['food_week_strip', 'fit_chip', 'plan_row', 'calorie_card_day'],
      () async {
        final strip = find.byType(FoodWeekStrip);
        final widget = t.widget<FoodWeekStrip>(strip);
        await tap(
          t,
          within(strip, control('${dayTitle('2026-10-12')}, counted')),
        );
        expect(t.widget<FoodWeekStrip>(strip).date, widget.date);
        expect(t.widget<FoodWeekStrip>(strip).marks, widget.marks);
        await tap(t, control('Fit what is left, 243 g'));
        for (final title in ['Log', 'Add to Lunch']) {
          await tap(t, find.text(title));
        }
        expect(find.text('1,358 to your 10,000 goal'), findsOneWidget);
      },
    ),
  );

  testWidgets(
    'gallery mood and steppers preserve measured and unknown examples',
    (t) => examples(
      t,
      ['mood_picker', 'mood_picker_blank', 'field_stepper'],
      () async {
        final moods = find.byType(MoodPicker);
        for (final (index, original) in [(0, 4), (1, null)]) {
          await tap(t, within(moods.at(index), control('Mood 3 of 5')));
          expect(t.widget<MoodPicker>(moods.at(index)).value, original);
        }
        final steps = find.byType(FieldStepper);
        for (final (index, original) in [(0, 1500), (1, null)]) {
          await tap(t, within(steps.at(index), control('Increase')));
          expect(t.widget<FieldStepper>(steps.at(index)).value, original);
        }
      },
    ),
  );

  testWidgets(
    'gallery workout, link and scrubber controls hold their authored state',
    (t) => examples(
      t,
      ['workout_context', 'live_counter_buttons', 'pressable', 'scrubber'],
      () async {
        final context = find.byType(WorkoutContextSelector);
        final tags = List.of(t.widget<WorkoutContextSelector>(context).tags);
        final option = within(
          context,
          find.byWidgetPredicate(
            (widget) =>
                widget is Pressable &&
                (widget.semanticLabel?.endsWith(', not selected') ?? false),
          ),
        );
        await tap(t, option.first);
        expect(t.widget<WorkoutContextSelector>(context).tags, tags);
        for (final label in [
          'One less rep',
          'One more rep',
          'Open the full night',
        ]) {
          await tap(t, control(label));
        }
        final scrubber = find.byType(Scrubber);
        final before = t.widget<Scrubber>(scrubber);
        await reveal(t, scrubber);
        final rect = t.getRect(scrubber);
        await t.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
        await t.pumpAndSettle();
        expect(t.widget<Scrubber>(scrubber).value, before.value);
        expect(find.text('Last night'), findsOneWidget);
      },
    ),
  );

  testWidgets(
    'gallery Settings and source rows do not open destructive or native actions',
    (t) => examples(t, ['set_row', 'source_row'], () async {
      for (final label in [
        'Manage notifications',
        'Units',
        'Delete everything on this device',
        'Sample\u2019s WHOOP band',
      ]) {
        await tap(t, find.text(label));
        expect(find.text('Settings row'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(find.text('Metric'), findsOneWidget);
      expect(find.text('iPhone'), findsOneWidget);
    }),
  );
}
