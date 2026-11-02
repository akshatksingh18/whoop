// Build 92: the nested-flow findings of Codex's extended Build 91 audit
// (9-13), asserting the repaired behaviour. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';

class _Repo extends LocalRepository {
  int timelineReads = 0;
  bool failOlder = false;
  bool failSave = false;
  int saves = 0;
  Map<String, JournalMetricValue> stored = {};
  String note = '';

  @override
  Future<List<String>> availableDays() async => ['2026-10-17', '2026-10-16'];
  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {'today_day': '2026-10-17'},
  };
  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async {
    timelineReads++;
    if (failOlder && date == '2026-10-16') throw StateError('synthetic');
    final at = DateTime.parse(date).millisecondsSinceEpoch ~/ 1000;
    return {
      'date': date,
      'day_start': at,
      'hr': [
        {'t': at + 60, 'v': 80},
        {'t': at + 120, 'v': 90},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayWear(String date) async => {};
  @override
  Future<List<JournalFieldSpec>> getJournalFields() async => [];
  @override
  Future<Map<String, JournalMetricValue>> getJournalMetrics(String date) async =>
      {...stored};
  @override
  Future<List<Map<String, dynamic>>> getJournal({String range = '30d'}) async =>
      [
        {'date': '2026-10-17', 'tags': <String>[], 'note': note},
      ];
  @override
  Future<List<String>> saveJournalEdit(
    String date, {
    required Map<String, JournalMetricValue?> changes,
    required Map<String, JournalMetricValue> base,
    List<String>? tags,
    List<String>? baseTags,
    String? note,
    String? baseNote,
  }) async {
    if (failSave) throw StateError('synthetic write failure');
    final conflicts = [
      for (final k in changes.keys)
        if (stored[k] != base[k]) k,
    ];
    if (conflicts.isNotEmpty) return conflicts;
    saves++;
    for (final e in changes.entries) {
      if (e.value == null) {
        stored.remove(e.key);
      } else {
        stored[e.key] = e.value!;
      }
    }
    if (note != null) this.note = note;
    return const [];
  }
}

Widget _app(AppState state, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: child),
    );

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build92_nested_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    await LocalDb.instance;
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  testWidgets('9: an open day breakdown re-reads on committed data', (t) async {
    final repo = _Repo(), state = AppState.forTesting()..repo = repo;
    addTearDown(state.dispose);
    await t.pumpWidget(_app(state, const DayTimelineScreen(day: '2026-10-17')));
    await _until(t, () => find.byType(DayHeartCard).evaluate().isNotEmpty);
    final before = repo.timelineReads;
    state.bumpInsights();
    await _until(t, () => repo.timelineReads > before);
  });

  testWidgets('10: a failed day switch never shows the old day graph', (
    t,
  ) async {
    final repo = _Repo(), state = AppState.forTesting()..repo = repo;
    addTearDown(state.dispose);
    await t.pumpWidget(_app(state, const DayTimelineScreen(day: '2026-10-17')));
    await _until(t, () => find.byType(DayHeartCard).evaluate().isNotEmpty);
    repo.failOlder = true;
    t.widget<DayNav>(find.byType(DayNav)).onDay('2026-10-16');
    await _until(
      t,
      () =>
          repo.timelineReads >= 2 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(t.widget<DayNav>(find.byType(DayNav)).day, '2026-10-16');
    expect(find.byType(DayHeartCard), findsNothing);
    expect(find.text('This day could not load'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('11: a meal with no calories recorded never reads 0 kcal', (
    t,
  ) async {
    await t.runAsync(
      () async => NutritionDb.put(
        await LocalDb.instance,
        const FoodEntry(
          id: 'unknown-meal',
          date: '2026-10-15',
          meal: 'breakfast',
          label: 'Synthetic food',
          proteinG: 10,
        ),
      ),
    );
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    await t.pumpWidget(
      _app(state, const MealPage(date: '2026-10-15', meal: 'breakfast')),
    );
    await _until(t, () => find.text('Synthetic food').evaluate().isNotEmpty);
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Calories not recorded for these foods'), findsOneWidget);
  });

  testWidgets('12: a failed Journal save is released, not stuck on Saving', (
    t,
  ) async {
    final repo = _Repo()..failSave = true;
    final state = AppState.forTesting()..repo = repo;
    addTearDown(state.dispose);
    await t.pumpWidget(_app(state, const JournalCompose(date: '2026-10-17')));
    await _until(t, () => find.text('Save').evaluate().isNotEmpty);
    await t.enterText(find.byType(TextField).last, 'Late dinner');
    await t.pump();
    t.widget<BigButton>(find.byType(BigButton)).onTap!();
    await _until(
      t,
      () => find.textContaining('Could not save').evaluate().isNotEmpty,
    );
    expect(find.text('Saving'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('13: saving the Journal keeps a newer water entry', (t) async {
    final repo = _Repo()
      ..stored = {'water_ml': const JournalMetricValue(250)};
    final state = AppState.forTesting()..repo = repo;
    addTearDown(state.dispose);
    await t.pumpWidget(_app(state, const JournalCompose(date: '2026-10-17')));
    await _until(t, () => find.text('Save').evaluate().isNotEmpty);
    // The band records more water while the editor stays open.
    repo.stored = {'water_ml': const JournalMetricValue(500)};
    await t.enterText(find.byType(TextField).last, 'Late dinner');
    await t.pump();
    t.widget<BigButton>(find.byType(BigButton)).onTap!();
    await _until(t, () => repo.saves == 1);
    expect(repo.stored['water_ml']!.value, 500);
    expect(repo.note, 'Late dinner');
  });

  test('12-13: the database writes a Journal edit as one checked patch', () async {
    const d = '2026-10-14';
    await LocalDb.putJournalMetrics(d, {
      'water_ml': const JournalMetricValue(250),
    });
    // Only the changed field is written; water stays.
    expect(
      await LocalDb.saveJournalEdit(
        d,
        changes: {'caffeine_mg': const JournalMetricValue(100)},
        base: const {},
        note: 'Long run',
        baseNote: '',
      ),
      isEmpty,
    );
    var now = await LocalDb.journalMetricsForDay(d);
    expect(now['water_ml']!.value, 250);
    expect(now['caffeine_mg']!.value, 100);
    // An editor that read 200 ml cannot overwrite the stored 250 ml.
    expect(
      await LocalDb.saveJournalEdit(
        d,
        changes: {'water_ml': const JournalMetricValue(300)},
        base: {'water_ml': const JournalMetricValue(200)},
      ),
      ['water_ml'],
    );
    now = await LocalDb.journalMetricsForDay(d);
    expect(now['water_ml']!.value, 250);
    // A deliberate clear removes the field.
    expect(
      await LocalDb.saveJournalEdit(
        d,
        changes: {'caffeine_mg': null},
        base: {'caffeine_mg': const JournalMetricValue(100)},
      ),
      isEmpty,
    );
    expect((await LocalDb.journalMetricsForDay(d)).containsKey('caffeine_mg'), isFalse);
  });
}
