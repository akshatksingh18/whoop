// Historical food and measured-maintenance display contracts, synthetic only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show io, ago;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-history-navigation');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..user = {
        'age': 30,
        'sex': 'f',
        'height_cm': 170,
        'weight_kg': 70,
        'kcal_target': 2000,
      };
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, Widget page) async {
    await localizedPage(t, Scaffold(body: page), app: app, settle: false);
    await io(t);
  }

  Future<void> put(
    String day,
    String id, {
    String meal = 'lunch',
    double? kcal = 400,
  }) async {
    await NutritionDb.put(
      await LocalDb.instance,
      FoodEntry(
        id: id,
        date: day,
        meal: meal,
        label: 'Synthetic $id',
        kcal: kcal,
        atTs: localDayStartSec(day)! + 12 * 3600,
      ),
    );
  }

  testWidgets(
    'day navigation returns to today and reselecting Food clears the historical view',
    (t) async {
      await open(t, const NutritionScreen());
      Finder daySwipe() =>
          find.byWidgetPredicate((w) => w is Swipe && w.label == 'Day');
      t.widget<Swipe>(daySwipe()).onPrevious!();
      await io(t);
      expect(
        t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
        ago(1),
      );
      expect(find.text('Back to today'), findsOneWidget);
      await t.tap(find.text('Back to today'));
      await io(t);
      expect(
        t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
        todayLabel(),
      );
      t.widget<Swipe>(daySwipe()).onPrevious!();
      await io(t);
      await t.tap(find.text('History').first);
      await io(t);
      shellReselect.value = (ShellDomain.nutrition, shellReselect.value.$2 + 1);
      await io(t);
      expect(
        t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
        todayLabel(),
      );
      expect(find.text('Back to today'), findsNothing);
      expect(t.widget<Swipe>(daySwipe()).onNext, isNull);
    },
  );
  testWidgets(
    'COV-48 collapsed food month invalidates its saved window before reopening',
    (t) async {
      final today = DateTime.parse(todayLabel());
      final first = dayLabelOf(DateTime(today.year, today.month - 1, 10));
      final second = dayLabelOf(DateTime(today.year, today.month - 1, 11));
      await put(first, 'prior-month');
      final db = await LocalDb.instance;
      final original = await db.query('food_entry', orderBy: 'id');
      await open(t, const NutritionScreen());
      await t.tap(find.text('History').first);
      await io(t);
      final title = MaterialLocalizations.of(
        t.element(find.byType(NutritionScreen)),
      ).formatMonthYear(DateTime.parse(first));
      final heading = find.text(title);
      await reveal(t, heading);
      await t.tap(heading);
      await io(t);
      expect(find.textContaining('1 day logged'), findsOneWidget);
      await reveal(t, heading);
      await t.tap(heading);
      await io(t);
      await t.runAsync(() => put(second, 'new-prior-month'));
      final saved = (await t.runAsync(
        () => db.query('food_entry', orderBy: 'id'),
      ))!;
      app.bumpInsights();
      await io(t);
      await reveal(t, heading);
      await t.tap(heading);
      await io(t);
      expect(find.textContaining('2 days logged'), findsOneWidget);
      expect(
        await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
        saved,
      );
      expect(
        saved.singleWhere((r) => r['id'] == 'prior-month'),
        original.single,
      );
      expect(app.user!['kcal_target'], 2000);
      expect(app.user!['weight_kg'], 70);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  for (final mode in ['steady', 'losing', 'uneven']) {
    testWidgets(
      'weight History $mode preserves the existing estimate and uncertainty disclosure',
      (t) async {
        await t.runAsync(() async {
          final db = await LocalDb.instance;
          for (var i = 27; i >= 0; i--) {
            await put(ago(i), 'history-$i', kcal: 2000);
            await NutritionDb.setDayMark(db, ago(i), 'complete');
            final weight = mode == 'steady'
                ? 70.0
                : mode == 'losing'
                ? 70 + i * .02
                : 70 + (i % 4) * 6.0;
            await BodyLogDb.putWeight(ago(i), weight, 'kg', historyOnly: false);
          }
        });
        await open(t, const NutritionScreen());
        await t.tap(find.text('History').first);
        await io(t);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('7-day trend'));
        if (mode == 'uneven') {
          expect(
            text,
            contains('Weight is too uneven to estimate maintenance yet'),
          );
          expect(
            text,
            isNot(contains('Estimated maintenance from food and weight:')),
          );
        } else {
          expect(text, contains('Estimated maintenance from food and weight:'));
          expect(
            text,
            contains(mode == 'steady' ? 'weight about steady' : 'losing'),
          );
          expect(text, contains('short-window conversion estimate'));
        }
        expect(app.user!['kcal_target'], 2000);
        expect(app.user!['weight_kg'], 70);
      },
    );
  }
  testWidgets(
    'COV-48 failed Copy a day source read preserves food and can reopen its review',
    (t) async {
      const from = '2021-04-06', to = '2021-04-07';
      await put(from, 'source');
      final db = await LocalDb.instance;
      final before = await db.query('food_entry', orderBy: 'id');
      await open(
        t,
        const SingleChildScrollView(child: NutritionDayView(date: to)),
      );
      final copy = find.textContaining('Copy a day').first;
      await reveal(t, copy);
      await t.runAsync(
        () => db.execute(
          'ALTER TABLE food_entry RENAME TO authored_hidden_food_entry',
        ),
      );
      try {
        await t.tap(copy);
        await t.pumpAndSettle();
        await t.tap(find.text('OK'));
        await io(t);
        expect(
          find.text('Food could not load. Try copying again.'),
          findsOneWidget,
        );
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(
          await t.runAsync(
            () => db.query('authored_hidden_food_entry', orderBy: 'id'),
          ),
          before,
        );
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_hidden_food_entry RENAME TO food_entry',
          ),
        );
      }
      await reveal(t, copy);
      await t.tap(copy);
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await io(t);
      expect(find.text('Copy a day'), findsOneWidget);
      expect(find.textContaining('Synthetic source'), findsWidgets);
      expect(
        await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
        before,
      );
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, to)),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
  for (final outcome in ['cancel', 'copy', 'refuse']) {
    testWidgets(
      'the dated Copy a day caller $outcome keeps source food and the target date',
      (t) async {
        final from = ago(2), to = ago(1);
        await put(from, 'known', meal: 'breakfast');
        await put(from, 'unknown', meal: 'snacks', kcal: null);
        await open(t, SingleChildScrollView(child: NutritionDayView(date: to)));
        await reveal(t, find.text('Copy a day'));
        await t.tap(find.text('Copy a day'));
        await t.pumpAndSettle();
        if (outcome == 'cancel') {
          await t.tap(find.text('Cancel').last);
          await io(t);
          expect(
            await t.runAsync(
              () async => NutritionDb.entriesForDay(await LocalDb.instance, to),
            ),
            isEmpty,
          );
          return;
        }
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .onDateChanged(DateTime.parse(from));
        await t.pumpAndSettle();
        await t.tap(find.text('OK').last);
        await io(t);
        expect(
          find.text('Untick anything you do not want, or change a portion.'),
          findsOneWidget,
        );
        expect(find.textContaining('calories unknown'), findsOneWidget);
        final db = (await t.runAsync(() => LocalDb.instance))!;
        if (outcome == 'refuse') {
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER synthetic_food_copy_refusal BEFORE INSERT ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic copy refusal'); END",
            ),
          );
        }
        try {
          final copy = find.byType(BigButton).last;
          await reveal(t, copy);
          await invokeControl(t, t.widget<BigButton>(copy).onTap);
          if (outcome == 'refuse') {
            expect(
              find.text(
                'Food was not copied. Your review is here; try logging again.',
              ),
              findsOneWidget,
            );
            expect(
              await t.runAsync(() => NutritionDb.entriesForDay(db, to)),
              isEmpty,
            );
            await t.runAsync(
              () => db.execute('DROP TRIGGER synthetic_food_copy_refusal'),
            );
            await invokeControl(t, t.widget<BigButton>(copy).onTap);
          }
          await io(t);
          final copied = (await t.runAsync(
            () => NutritionDb.entriesForDay(db, to),
          ))!;
          expect(copied, hasLength(2));
          expect(
            copied.map((e) => e.meal),
            unorderedEquals(['breakfast', 'snacks']),
          );
          expect(
            copied.singleWhere((e) => e.label == 'Synthetic unknown').kcal,
            isNull,
          );
          expect(copied.every((e) => e.date == to), isTrue);
          expect(
            await t.runAsync(() => NutritionDb.entriesForDay(db, from)),
            hasLength(2),
          );
        } finally {
          await t.runAsync(
            () => db.execute(
              'DROP TRIGGER IF EXISTS synthetic_food_copy_refusal',
            ),
          );
        }
      },
    );
  }
}
