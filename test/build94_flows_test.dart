// Build 94: Codex's audit of the Build 94 candidate (N01-N20) and Akshat's
// Food requests, asserting the repaired behaviour against the real synthetic
// SQLite store and the real widgets. Synthetic data only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/food_left.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Widget _app(AppState state, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
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

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);

BigButton _button(WidgetTester t, String label) =>
    t.widget<BigButton>(find.widgetWithText(BigButton, label));

const _sausage = <String, Object?>{
  'key': 'my:b94-probe',
  'label': 'Synthetic sausage',
  'unit': 'g',
  'kcal_100': 200,
  'protein_g_100': 10,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build94_flows_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final table in [
      'food_entry',
      'food_def',
      'sessions',
      'lift_log',
      'metric_series',
      'metric_series_version',
      'day_result',
    ]) {
      try {
        await db.delete(table);
      } catch (_) {}
    }
  });

  test('N01: a session rewrite keeps the privacy flag and effort', () async {
    final row = {
      'id': 'b94-s1',
      'start_ts': 1790000000,
      'end_ts': 1790003600,
      'type': 'run',
      'status': 'done',
      'created_at': 1790000000,
    };
    await LocalDb.putSession(row);
    await LocalDb.setSessionPrivate('b94-s1', true);
    await db.update('sessions', {'rpe': 7}, where: "id = 'b94-s1'");
    // A retime writes the row again without either field.
    await LocalDb.putSession({...row, 'end_ts': 1790004000});
    final back = (await db.query('sessions', where: "id = 'b94-s1'")).single;
    expect(back['private'], 1);
    expect(back['rpe'], 7);
    expect(back['end_ts'], 1790004000);
  });

  test('N02: the Lift Log CSV leaves out a private workout', () async {
    final t0 = DateTime(2026, 10, 1, 18);
    for (final (id, private) in [('b94-open', false), ('b94-hidden', true)]) {
      await LocalDb.putSession({
        'id': id,
        'start_ts': t0.millisecondsSinceEpoch ~/ 1000,
        'end_ts': t0.millisecondsSinceEpoch ~/ 1000 + 3000,
        'type': 'strength',
        'status': 'done',
        'created_at': 1790000000,
      });
      await LocalDb.setSessionPrivate(id, private);
      final w = LiftWorkout(startedAt: t0, sessionId: id);
      final e = w.addExercise(
        name: private ? 'Hidden press' : 'Open press',
        loadMode: LiftLoadMode.total,
      );
      w.addSet(e, reps: 5, load: 100, at: t0.add(const Duration(minutes: 5)));
      w.finish(t0.add(const Duration(minutes: 50)));
      await LiftLogDb.save(w);
    }
    final csv = await LiftLogDb.csv();
    expect(csv, contains('Open press'));
    expect(csv, isNot(contains('Hidden press')));
  });

  test('N06: a restore keeps a finalized day\'s chart values', () async {
    await db.insert('metric_series', {
      'date': '2026-09-01',
      'key': 'readiness',
      'value': 99.0,
    });
    await db.insert('metric_series', {
      'date': '2026-09-02',
      'key': 'readiness',
      'value': 77.0,
    });
    final folder = await Directory.systemTemp.createTemp('build94_restore_');
    final file = p.join(folder.path, 'export.db');
    await db.execute('VACUUM INTO ?', [file]);
    try {
      await db.delete('metric_series');
      await db.insert('day_result', {
        'day_id': '2026-09-01',
        'algo_version': 1,
        'payload_json': '{}',
        'computed_at': 1,
        'finalized': 1,
      });
      await db.insert('metric_series', {
        'date': '2026-09-01',
        'key': 'readiness',
        'value': 50.0,
      });
      await LocalDb.importFromDbFile(file);
      final rows = {
        for (final r in await db.query(
          'metric_series',
          where: "key = 'readiness'",
        ))
          r['date']: r['value'],
      };
      expect(rows['2026-09-01'], 50.0, reason: 'finalized here, kept');
      expect(rows['2026-09-02'], 77.0, reason: 'not finalized, restored');
    } finally {
      await File(file).delete();
      await folder.delete();
    }
  });

  test('N09: one weight parser for a comma or a point', () {
    expect(parseWeightText('75,5'), 75.5);
    expect(parseWeightText(' 75.5 '), 75.5);
    expect(parseWeightText(''), isNull);
    expect(parseWeightText('75,5,1'), isNull);
    expect(parseWeightText('abc'), isNull);
  });

  test('N13: rows restored without a scored day are something landed', () {
    expect(const ImportOutcome(source: 'Backup').nothingLanded, isTrue);
    expect(
      const ImportOutcome(source: 'Backup', records: 3).nothingLanded,
      isFalse,
    );
  });

  testWidgets('N14: an unsaved form is visible to external navigation', (
    t,
  ) async {
    var dirty = true;
    await t.pumpWidget(
      MaterialApp(
        home: DirtyPopScope(dirty: () => dirty, child: const SizedBox()),
      ),
    );
    expect(DirtyPopScope.anyDirty, isTrue);
    dirty = false;
    expect(DirtyPopScope.anyDirty, isFalse);
    dirty = true;
    final before = DirtyPopScope.closed.value;
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(DirtyPopScope.anyDirty, isFalse, reason: 'the form closed');
    expect(DirtyPopScope.closed.value, before + 1);
  });

  testWidgets('N08: an amount in a removed unit is asked for again', (
    t,
  ) async {
    _tall(t);
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    await t.pumpWidget(
      _app(
        state,
        const GramsSheet(
          def: _sausage,
          initial: 2,
          initialUnit: 'links',
          action: 'Done',
        ),
      ),
    );
    await t.pump();
    expect(find.textContaining('Saved as 2 links'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(_button(t, 'Done').onTap, isNull, reason: 'never 2 g');
  });

  testWidgets('Food: 0 turns Save into Remove on a logged entry', (t) async {
    _tall(t);
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    await t.pumpWidget(
      _app(
        state,
        const GramsSheet(
          def: _sausage,
          initial: 50,
          initialUnit: 'g',
          action: 'Save',
          zeroRemoves: true,
        ),
      ),
    );
    await t.pump();
    await t.enterText(find.byType(TextField).first, '0');
    await t.pump();
    expect(find.text('An amount of 0 removes this entry from the day.'),
        findsOneWidget);
    expect(_button(t, 'Remove').onTap, isNotNull);
  });

  testWidgets('Food: 0 is not an amount when adding a new food', (t) async {
    _tall(t);
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    await t.pumpWidget(_app(state, const GramsSheet(def: _sausage)));
    await t.pump();
    await t.enterText(find.byType(TextField).first, '0');
    await t.pump();
    expect(find.widgetWithText(BigButton, 'Remove'), findsNothing);
    expect(_button(t, 'Add').onTap, isNull);
  });

  testWidgets('Food: the Food tab meal card swipes to delete, with Undo', (
    t,
  ) async {
    _tall(t);
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    final e = FoodEntry(
      id: 'b94-e1',
      date: todayLabel(),
      meal: 'lunch',
      label: 'Synthetic soup',
      kcal: 300,
    );
    await t.runAsync(() => NutritionDb.put(db, e));
    var changed = 0;
    await t.pumpWidget(
      _app(
        state,
        MealCard(
          date: todayLabel(),
          meal: 'lunch',
          entries: [e],
          onChanged: () => changed++,
        ),
      ),
    );
    expect(find.byType(SwipeDelete), findsOneWidget);
    // The same delete the swipe calls, past its confirm.
    final ctx = t.element(find.byType(MealCard));
    await t.runAsync(
      () => deleteDiaryEntry(
        ctx,
        e,
        confirm: false,
        reload: () async => changed++,
      ),
    );
    expect(changed, 1, reason: 'the day reloads after the delete');
    await t.pump();
    expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
    expect(find.text('Deleted Synthetic soup'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 600)); // the bar slides in
    await t.tap(find.text('Undo'));
    await _until(t, () => changed >= 2);
    final back = await t.runAsync(() => db.query('food_entry'));
    expect(back, hasLength(1));
  });

  testWidgets('Food: Quick add shows what is left of the day as you type', (
    t,
  ) async {
    _tall(t);
    final state = AppState.forTesting()
      ..user = {'kcal_target': 2000.0, 'protein_target': 150.0};
    addTearDown(state.dispose);
    await t.runAsync(
      () => NutritionDb.put(
        db,
        FoodEntry(
          id: 'b94-eaten',
          date: todayLabel(),
          meal: 'breakfast',
          label: 'Synthetic oats',
          kcal: 500,
          proteinG: 20,
        ),
      ),
    );
    await t.pumpWidget(
      _app(state, QuickAddSheet(date: todayLabel(), meal: 'lunch')),
    );
    await _until(t, () => find.byType(LeftAfterCard).evaluate().isNotEmpty);
    expect(find.textContaining('1,500 kcal left'), findsOneWidget);
    await t.enterText(_field('Calories (kcal)'), '300');
    await t.pump();
    expect(find.textContaining('1,200 kcal left'), findsOneWidget);
  });
}
