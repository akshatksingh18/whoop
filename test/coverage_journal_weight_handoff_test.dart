// The existing Gallery-reachable Journal editor, not a new personal Sleep flow.
// Real repository and authored SQLite history; no personal measurements.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart' show invokeControl;

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);
Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> until(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
  expect(t.takeException(), isNull);
}

Future<void> press(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late UnitsController units;
  const day = '2021-04-06';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-weight-handoff');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    units = UnitsController.withUnits();
  });
  tearDown(() {
    app.dispose();
    units.dispose();
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t, {String date = day}) async {
    t.view.physicalSize = const Size(900, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<UnitsController>.value(value: units),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => JournalCompose(date: date),
                  ),
                ),
                child: const Text('Existing gallery journal route'),
              ),
            ),
          ),
        ),
      ),
    );
    await press(t, find.text('Existing gallery journal route'));
    await until(t, () => action('Enter weight').evaluate().isNotEmpty);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    });
  }

  Future<void> saveJournal(WidgetTester t) async {
    final f = find.widgetWithText(BigButton, 'Save');
    await t.ensureVisible(f);
    await invokeControl(t, t.widget<BigButton>(f).onTap);
    expect(find.text('Existing gallery journal route'), findsOneWidget);
  }

  Future<void> dialogSave(WidgetTester t) => press(
    t,
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Save'),
    ),
  );

  testWidgets(
    'Cancel preserves a stored weight and the rest of the old-day journal',
    (t) async {
      await t.runAsync(() async {
        await LocalDb.putJournal(day, '["travel"]', 'Authored older note');
        await LocalDb.putJournalMetrics(day, {
          'weight_kg': const JournalMetricValue(70),
          'caffeine_mg': const JournalMetricValue(80, atMinuteOfDay: 600),
        });
      });
      await open(t);
      await press(t, action('Enter weight'));
      expect(t.widget<TextField>(field('Weight (kg)')).controller!.text, '70');
      await t.enterText(field('Weight (kg)'), '99');
      await press(t, find.widgetWithText(TextButton, 'Cancel'));
      await saveJournal(t);
      final values = await t.runAsync(() => LocalDb.journalMetricsForDay(day));
      expect(values!['weight_kg']!.value, 70);
      expect(values['caffeine_mg']!.atMinuteOfDay, 600);
      expect(
        (await t.runAsync(
          () => LocalDb.journalRows(date: day),
        ))!.single['note'],
        'Authored older note',
      );
    },
  );

  for (final imperial in [false, true]) {
    testWidgets(
      '${imperial ? 'lb' : 'kg'} typed entry saves only the viewed historical day',
      (t) async {
        if (imperial) {
          units.dispose();
          units = UnitsController.withUnits(weight: 'lb');
        }
        await open(t);
        await press(t, action('Enter weight'));
        expect(
          find.text(
            'What you or your scale read. The band does not measure this.',
          ),
          findsOneWidget,
        );
        final input = field(imperial ? 'Weight (lb)' : 'Weight (kg)');
        await t.enterText(input, imperial ? '154.5' : '70.25');
        await dialogSave(t);
        expect(
          await t.runAsync(() => LocalDb.journalMetricsForDay(day)),
          isEmpty,
          reason: 'Dialog edits remain unsaved until the editor Save',
        );
        await saveJournal(t);
        final stored = await t.runAsync(
          () => LocalDb.journalMetricsForDay(day),
        );
        expect(
          stored!['weight_kg']!.value,
          closeTo(imperial ? 154.5 * .45359237 : 70.25, 1e-10),
        );
        expect(
          await t.runAsync(() => LocalDb.journalMetricsForDay(todayLabel())),
          isEmpty,
        );
      },
    );
  }

  testWidgets(
    'unreadable input keeps the dialog and saved value until corrected',
    (t) async {
      await t.runAsync(
        () => LocalDb.putJournalMetrics(day, {
          'weight_kg': const JournalMetricValue(70),
        }),
      );
      await open(t);
      await press(t, action('Enter weight'));
      await t.enterText(field('Weight (kg)'), 'not a number');
      await dialogSave(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('is not a number. Nothing was saved.'),
        findsOneWidget,
      );
      expect(
        (await t.runAsync(
          () => LocalDb.journalMetricsForDay(day),
        ))!['weight_kg']!.value,
        70,
      );
      await t.enterText(field('Weight (kg)'), '71');
      await dialogSave(t);
      await saveJournal(t);
      expect(
        (await t.runAsync(
          () => LocalDb.journalMetricsForDay(day),
        ))!['weight_kg']!.value,
        71,
      );
    },
  );

  testWidgets(
    'Clear removes only this weight after editor Save, keeping zero and provenance',
    (t) async {
      await t.runAsync(
        () => LocalDb.putJournalMetrics(day, {
          'weight_kg': const JournalMetricValue(70),
          'caffeine_mg': const JournalMetricValue(0, atMinuteOfDay: 615),
        }),
      );
      await open(t);
      await press(t, action('Enter weight'));
      await press(t, find.widgetWithText(TextButton, 'Clear'));
      expect(find.text('Not entered'), findsWidgets);
      expect(
        (await t.runAsync(
          () => LocalDb.journalMetricsForDay(day),
        ))!['weight_kg'],
        isNotNull,
      );
      await saveJournal(t);
      final values = await t.runAsync(() => LocalDb.journalMetricsForDay(day));
      expect(values!.containsKey('weight_kg'), isFalse);
      expect(values['caffeine_mg']!.value, 0);
      expect(values['caffeine_mg']!.atMinuteOfDay, 615);
    },
  );

  for (final imperial in [false, true]) {
    testWidgets(
      'trend retains calendar gaps, authored units and no measured-weight claim ${imperial ? 'lb' : 'kg'}',
      (t) async {
        if (imperial) {
          units.dispose();
          units = UnitsController.withUnits(weight: 'lb');
        }
        final now = DateTime.now();
        String ago(int n) =>
            dayLabelOf(DateTime(now.year, now.month, now.day - n));
        await t.runAsync(() async {
          for (final e in [(5, 70.0), (3, 71.0), (0, 72.0)]) {
            await LocalDb.putJournalMetrics(ago(e.$1), {
              'weight_kg': JournalMetricValue(e.$2),
            });
          }
          await LocalDb.putJournalMetrics(ago(2), {
            'weight_kg': const JournalMetricValue(0),
          });
        });
        await open(t, date: ago(0));
        await press(t, action('See the weight trend'));
        await until(
          t,
          () => find
              .byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is LineChart,
              )
              .evaluate()
              .isNotEmpty,
        );
        final line =
            t
                    .widget<CustomPaint>(
                      find.byWidgetPredicate(
                        (w) => w is CustomPaint && w.painter is LineChart,
                      ),
                    )
                    .painter!
                as LineChart;
        expect(line.d, hasLength(6));
        expect(line.d[1], isNull);
        expect(line.d[3], isNull);
        expect(line.d[4], isNull);
        expect(line.fill, isFalse);
        expect(
          line.d.first,
          closeTo(imperial ? double.parse(units.weightField(70)) : 70, 1e-9),
        );
        expect(
          find.textContaining('the band does not measure weight'),
          findsOneWidget,
        );
        expect(find.textContaining('3 days entered.'), findsOneWidget);
        expect(
          (await t.runAsync(
            () => LocalDb.journalMetricsForDay(ago(2)),
          ))!['weight_kg']!.value,
          0,
          reason: 'Invalid weight is not silently rewritten',
        );
      },
    );
  }

  testWidgets(
    'one usable day explains the thin trend without creating extra history',
    (t) async {
      await open(t, date: todayLabel());
      await press(t, action('See the weight trend'));
      await until(
        t,
        () => find.text('Not enough entries for a trend').evaluate().isNotEmpty,
      );
      expect(find.textContaining('needs at least two days'), findsOneWidget);
      expect(
        await t.runAsync(() => LocalDb.journalMetricsForDay(todayLabel())),
        isEmpty,
      );
    },
  );
}
