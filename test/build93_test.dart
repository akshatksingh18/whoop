// Build 93: the cross-flow findings of Codex's Build 92 audit (C01-C06),
// asserting the repaired behaviour against the real synthetic SQLite store.
// Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

class _Repo extends LocalRepositoryImpl {
  _Repo() : super(getProfileMap: () => null);
  int saves = 0;
  @override
  Future<List<String>> saveJournalEdit(
    String date, {
    required Map<String, JournalMetricValue?> changes,
    required Map<String, JournalMetricValue> base,
    List<String>? tags,
    List<String>? baseTags,
    String? note,
    String? baseNote,
  }) {
    saves++;
    return super.saveJournalEdit(
      date,
      changes: changes,
      base: base,
      tags: tags,
      baseTags: baseTags,
      note: note,
      baseNote: baseNote,
    );
  }
}

Widget _app(AppState state, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 40));
  }
  expect(done(), isTrue);
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _seedJournal() async {
  await LocalDb.putJournalMetrics(todayLabel(), {
    'mood': const JournalMetricValue(1),
    'water_ml': const JournalMetricValue(250),
  });
  await LocalDb.putJournal(todayLabel(), '[]', 'base');
}

Future<void> _press(WidgetTester t, String label) async {
  await t.runAsync(() async {
    final dynamic action = t
        .widget<BigButton>(find.widgetWithText(BigButton, label))
        .onTap;
    await action();
  });
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build93_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final table in [
      'food_entry',
      'food_day_count',
      'food_def',
      'meal_template',
      'body_weight_reading',
      'body_weight',
      'journal_metric',
      'journal',
    ]) {
      await db.delete(table);
    }
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  test(
    'C03: a unit the food no longer has is left out, never relabelled',
    () async {
      await NutritionDb.putFoodDef(db, {
        'key': 'my:probe',
        'label': 'Synthetic food',
        'unit': 'g',
        'kcal_100': 200,
      });
      final r = await MyFoods.saveMeal(
        db,
        label: 'Synthetic meal',
        meal: 'lunch',
        entries: const [
          FoodEntry(
            id: 'a',
            date: '2026-10-01',
            meal: 'lunch',
            label: 'Synthetic food',
            foodKey: 'my:probe',
            quantity: 50,
            unit: 'g',
            kcal: 100,
          ),
          FoodEntry(
            id: 'b',
            date: '2026-10-01',
            meal: 'lunch',
            label: 'Synthetic food',
            foodKey: 'my:probe',
            quantity: 2,
            unit: 'links',
            kcal: 200,
          ),
        ],
      );
      expect(r.saved, 1);
      expect(r.skipped, 1);
      final m = (await MyFoods.meals(db)).single;
      expect(m.units['my:probe'], 'g');
      expect(m.items.map((x) => x.$2).toList(), [50]);
    },
  );

  testWidgets('C04: a failed Quick add saves no food, even on Retry', (
    t,
  ) async {
    _tall(t);
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    await t.runAsync(
      () => db.execute(
        "CREATE TRIGGER b93_reject BEFORE INSERT ON food_entry "
        "BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      ),
    );
    try {
      await t.pumpWidget(
        _app(state, QuickAddSheet(date: todayLabel(), meal: 'lunch')),
      );
      await t.enterText(_field('Name'), 'Synthetic retry food');
      await t.enterText(_field('Calories (kcal)'), '250');
      await t.ensureVisible(find.text('Save to My foods'));
      await t.tap(find.text('Save to My foods'));
      await t.pump();
      await t.ensureVisible(find.text('Add'));
      await _press(t, 'Add');
      await _until(
        t,
        () => find.textContaining('Could not save').evaluate().isNotEmpty,
      );
      await _press(t, 'Add');
      await _until(
        t,
        () => find.textContaining('Could not save').evaluate().isNotEmpty,
      );
      expect((await t.runAsync(() => db.query('food_def')))!, isEmpty);
      expect((await t.runAsync(() => db.query('food_entry')))!, isEmpty);
    } finally {
      await t.runAsync(() => db.execute('DROP TRIGGER b93_reject'));
    }
  });

  testWidgets(
    'C01: resolving a conflict never pushes back an old untouched value',
    (t) async {
      _tall(t);
      await t.runAsync(_seedJournal);
      final repo = _Repo(), state = AppState.forTesting()..repo = repo;
      addTearDown(state.dispose);
      await t.pumpWidget(_app(state, JournalCompose(date: todayLabel())));
      await _until(t, () => find.text('Save').evaluate().isNotEmpty);
      t.widget<MoodPicker>(find.byType(MoodPicker)).onChanged(3);
      await t.pump();
      // Another writer: mood 2 and water 500.
      await t.runAsync(
        () => LocalDb.putJournalMetrics(todayLabel(), {
          'mood': const JournalMetricValue(2),
          'water_ml': const JournalMetricValue(500),
        }),
      );
      await _press(t, 'Save');
      await _until(
        t,
        () => find.textContaining('Changed elsewhere').evaluate().isNotEmpty,
      );
      expect(t.widget<MoodPicker>(find.byType(MoodPicker)).value, 2);
      await _press(t, 'Save');
      final values = await t.runAsync(
        () => LocalDb.journalMetricsForDay(todayLabel()),
      );
      expect(values!['water_ml']!.value, 500);
      expect(values['mood']!.value, 2);
    },
  );

  testWidgets('C05: a tag added elsewhere does not block saving the note', (
    t,
  ) async {
    _tall(t);
    await t.runAsync(_seedJournal);
    final repo = _Repo(), state = AppState.forTesting()..repo = repo;
    addTearDown(state.dispose);
    await t.pumpWidget(_app(state, JournalCompose(date: todayLabel())));
    await _until(t, () => find.text('Save').evaluate().isNotEmpty);
    await t.enterText(find.byType(TextField).last, 'my draft');
    await t.runAsync(
      () => LocalDb.putJournal(todayLabel(), '["travel"]', 'base'),
    );
    await _press(t, 'Save');
    await _until(t, () => repo.saves == 1);
    final rows = await t.runAsync(() => LocalDb.journalRows());
    expect(rows!.single['note'], 'my draft');
    expect(rows.single['tags_json'], '["travel"]');
  });

  testWidgets(
    'C02: deleting today\'s first weigh-in moves the profile weight',
    (t) async {
      final day = todayLabel(), d = DateTime.parse(todayLabel());
      await t.runAsync(() async {
        await BodyLogDb.putWeight(
          day,
          80,
          'kg',
          at: DateTime(d.year, d.month, d.day, 8),
        );
        await BodyLogDb.putWeight(
          day,
          81,
          'kg',
          at: DateTime(d.year, d.month, d.day, 9),
        );
      });
      final state = AppState.forTesting()..user = {'weight_kg': 80.0};
      addTearDown(state.dispose);
      await t.pumpWidget(_app(state, BodyEntryScreen(unit: 'kg', date: day)));
      final first = find.byWidgetPredicate(
        (w) =>
            w is Pressable &&
            (w.semanticLabel ?? '').contains('80 kg') &&
            (w.semanticLabel ?? '').contains('. Delete'),
      );
      await _until(t, () => first.evaluate().isNotEmpty);
      t.widget<Pressable>(first).onTap!();
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await _until(t, () => state.user!['weight_kg'] == 81.0);
      final row = await t.runAsync(() => BodyLogDb.weightOn(day));
      expect(row!.kg, 81);
    },
  );

  testWidgets('C06: an old-night link says it is outside the chart', (t) async {
    final now = DateTime.now();
    final old = dayLabelOf(now.subtract(const Duration(days: 120)));
    final route = MetricDetail.at('resting_hr', old);
    final data = MetricData(
      series: [
        (
          t:
              DateTime(
                now.year,
                now.month,
                now.day,
                12,
              ).millisecondsSinceEpoch ~/
              1000,
          v: 60.0,
        ),
      ],
      daysAvailable: 180,
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: MetricDetail(
          'resting_hr',
          range: route.range,
          day: route.day,
          data: data,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining('older than this chart reaches'),
      findsOneWidget,
    );
  });
}
