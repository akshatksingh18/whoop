// Build 93: the cross-flow findings of Codex's Build 92 audit (C01-C06) and
// its full-flow audit (F01-F15), asserting the repaired behaviour against the
// real synthetic SQLite store.
// Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/csv_export.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
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
      'strength_set',
      'session_detail',
      'sessions',
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
  test('F01: what was typed during a workout survives a reopen', () async {
    final base = ActivityResult(
      allActivities.first,
      start: DateTime(2026, 10, 1, 7),
      duration: const Duration(minutes: 30),
    );
    final typed = base.copyWith(
      lapSecs: const [61, 63],
      poolLengthM: 25,
      stroke: 'free',
      rounds: const [IntervalRound(30, 15, avgHr: 150)],
      poses: const ['plank'],
      breathsPerMin: 6,
      gameScore: const [(21, 18)],
    );
    final json = enteredDetailJson(typed);
    expect(enteredDetailJson(base), isNull);
    await LocalDb.putSession({
      'id': 'f01',
      'start_ts': 1790000000,
      'end_ts': 1790001800,
      'type': 'swim',
      'status': 'done',
      'created_at': 1790000000,
    });
    await LocalDb.putSessionDetail('f01', json!);
    final back = withEnteredDetail(base, await LocalDb.sessionDetail('f01'));
    expect(back.lapSecs, [61, 63]);
    expect(back.poolLengthM, 25);
    expect(back.stroke, 'free');
    expect(back.rounds.single.avgHr, 150);
    expect(back.poses, ['plank']);
    expect(back.breathsPerMin, 6);
    expect(back.gameScore, [(21, 18)]);
    // A garbled row reopens the workout without its detail, never throws.
    expect(withEnteredDetail(base, '{"pool": "x"}').poolLengthM, isNull);
    // Deleting the workout deletes what was typed with it.
    await LocalDb.deleteSession('f01');
    expect(await LocalDb.sessionDetail('f01'), isNull);
  });

  test('F03: a private workout and its sets stay out of the CSV', () async {
    for (final (id, private) in [('open', 0), ('hidden', 1)]) {
      await LocalDb.putSession({
        'id': id,
        'start_ts': 1790000000 + private * 7200,
        'end_ts': 1790001800 + private * 7200,
        'type': 'strength',
        'status': 'done',
        'created_at': 1790000000,
      });
      await LocalDb.setSessionPrivate(id, private == 1);
      await db.insert('strength_set', {
        'session_id': id,
        'seq': 0,
        'exercise_key': 'bench_press',
        'set_index': 1,
        'reps': 5,
        'at_ts': 1790000100 + private * 7200,
      });
    }
    String sql(String name) =>
        kCsvExportSets.firstWhere((x) => x.name == name).sql;
    final workouts = await db.rawQuery(sql('workouts'));
    expect(workouts, hasLength(1));
    expect(workouts.single['start_ts'], 1790000000);
    final sets = await db.rawQuery(sql('strength'));
    expect(sets.map((r) => r['session_id']), ['open']);
  });

  test('C02: a history-only weight never becomes the profile weight', () async {
    final today = todayLabel();
    final d = DateTime.parse(today);
    final yesterday = dayLabelOf(DateTime(d.year, d.month, d.day - 1, 12));
    await BodyLogDb.putWeight(yesterday, 70, 'kg', historyOnly: true);
    final state = AppState.forTesting()..user = {'weight_kg': 80.0};
    addTearDown(state.dispose);
    // Today's only reading was just deleted: nothing current is left.
    await syncProfileWeightAfterDelete(state, today);
    expect(state.user!['weight_kg'], 80.0);
    // An older reading that is current does take over.
    final before = dayLabelOf(DateTime(d.year, d.month, d.day - 2, 12));
    await BodyLogDb.putWeight(before, 71, 'kg', historyOnly: false);
    await syncProfileWeightAfterDelete(state, today);
    expect(state.user!['weight_kg'], 71.0);
  });

  test('C09: a weekly reminder reports when it was not scheduled', () async {
    final ok = await NotificationService.instance.scheduleWeekly(
      id: NotificationService.idBodyReminder,
      category: NotifCategory.reminders,
      title: 'Measurement day',
      body: 'Synthetic',
      weekday: DateTime.monday,
      hour: 8,
      minute: 0,
    );
    // No notification permission in a test: never reported as set.
    expect(ok, isFalse);
  });

  testWidgets('F14: a changed form asks before it is left', (t) async {
    var dirty = false;
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: Text('Under')),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => DirtyPopScope(
          dirty: () => dirty,
          child: const Scaffold(body: Text('Form')),
        ),
      ),
    );
    await t.pumpAndSettle();
    // Clean: leaves at once.
    await key.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Under'), findsOneWidget);
    expect(find.text('Form'), findsNothing);

    dirty = true;
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => DirtyPopScope(
          dirty: () => dirty,
          child: const Scaffold(body: Text('Form')),
        ),
      ),
    );
    await t.pumpAndSettle();
    await key.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('Form'), findsOneWidget);
    await key.currentState!.maybePop();
    await t.pumpAndSettle();
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(find.text('Form'), findsNothing);
    expect(find.text('Under'), findsOneWidget);
  });
}
