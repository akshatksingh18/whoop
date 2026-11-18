// Nap correction controls against authored proposals and the real edit table.
// Recalculation is substituted; these checks do not certify sleep detection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/naps.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

const day = '2021-04-06';
int epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

class Repo extends LocalRepositoryImpl {
  Repo() : super(getProfileMap: () => {});
  bool fail = false;
  final held = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> getDayNaps(String date) {
    if (fail) throw StateError('synthetic nap read refusal');
    return held[date]?.future ?? super.getDayNaps(date);
  }
}

class App extends AppState {
  App() : super.forTesting();
  final updates = <String?>[];
  @override
  Future<void> reanalyzeForNapEdit([String? day]) async {
    updates.add(day);
  }
}

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tap(WidgetTester t, String text) async {
  final f = find.text(text);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Repo repo;
  late App app;
  late GlobalKey<NavigatorState> nav;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/nap-actions',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  Future<void> seed(String date, List<Map<String, dynamic>> naps) =>
      LocalDb.putDayResult(
        dayId: date,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'naps': {'value': naps},
        }),
        windowJson: '{}',
        finalized: false,
      );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    repo = Repo();
    app = App()..repo = repo;
    nav = GlobalKey<NavigatorState>();
    await seed(day, []);
  });
  tearDown(() async {
    for (final pending in repo.held.values) {
      if (!pending.isCompleted) pending.complete({'naps': [], 'nap_min': 0});
    }
    await db.execute('DROP TRIGGER IF EXISTS synthetic_nap_refusal');
    app.dispose();
    DayClock.install([], []);
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {String date = day}) async {
    t.view.physicalSize = const Size(430, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          navigatorKey: nav,
          theme: buildTheme(Brightness.light),
          home: NapsScreen(day: date),
        ),
      ),
    );
    await flush(t);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }

  Future<void> pick(WidgetTester t, TimeOfDay? from, TimeOfDay? to) async {
    await tap(t, 'Log a nap');
    expect(find.byType(TimePickerDialog), findsOneWidget);
    nav.currentState!.pop(from);
    await flush(t);
    if (from == null) return;
    expect(find.byType(TimePickerDialog), findsOneWidget);
    nav.currentState!.pop(to);
    await flush(t);
  }

  Future<List<Map<String, dynamic>>> edits(
    WidgetTester t, {
    String date = day,
  }) async => (await t.runAsync(() => LocalDb.napEdits(date)))!;

  for (final cancelStart in [false, true]) {
    testWidgets(
      'cancelling the ${cancelStart ? 'start' : 'end'} picker writes no nap',
      (t) async {
        await open(t);
        await pick(
          t,
          cancelStart ? null : const TimeOfDay(hour: 14, minute: 0),
          null,
        );
        expect(await edits(t), isEmpty);
        expect(app.updates, isEmpty);
      },
    );
  }
  for (final to in [
    const TimeOfDay(hour: 14, minute: 4),
    const TimeOfDay(hour: 21, minute: 0),
  ]) {
    testWidgets(
      'nap window ending ${to.hour}:${to.minute} is refused by the shared duration rule',
      (t) async {
        await open(t);
        await pick(t, const TimeOfDay(hour: 14, minute: 0), to);
        expect(
          find.textContaining('between 5 minutes and 6 hours'),
          findsOneWidget,
        );
        expect(await edits(t), isEmpty);
        expect(app.updates, isEmpty);
      },
    );
  }
  testWidgets(
    'a future nap cannot become recorded sleep',
    (t) => withClock(Clock.fixed(DateTime(2021, 4, 6, 12)), () async {
      await open(t);
      await pick(
        t,
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 14, minute: 30),
      );
      expect(
        find.text('That nap has not ended yet. Log it once you are up.'),
        findsOneWidget,
      );
      expect(await edits(t), isEmpty);
    }),
  );
  testWidgets('historical manual nap uses that day and remains a self report', (
    t,
  ) async {
    await open(t);
    await pick(
      t,
      const TimeOfDay(hour: 14, minute: 0),
      const TimeOfDay(hour: 14, minute: 30),
    );
    final rows = await edits(t);
    expect(rows, hasLength(1));
    expect(rows.single['start_ts'], epoch(DateTime(2021, 4, 6, 14)));
    expect(rows.single['end_ts'], epoch(DateTime(2021, 4, 6, 14, 30)));
    expect(rows.single['source'], 'manual');
    final merged = (await t.runAsync(() => repo.getDayNaps(day)))!;
    expect((merged['naps'] as List).single['confidence'], isNull);
    expect(app.updates, [day]);
    expect(await edits(t, date: todayLabel()), isEmpty);
  });
  testWidgets(
    'past-midnight nap uses the recorded DST calendar without a fixed 24-hour jump',
    (t) async {
      const dstDay = '2026-03-07';
      final first = epoch(DateTime.utc(2026, 3, 5));
      final changes = [ZoneChange(first, 'America/New_York')];
      DayClock.install(
        buildDayZones(
          fromSec: first,
          throughSec: epoch(DateTime.utc(2026, 3, 10)),
          changes: changes,
        ),
        changes,
      );
      await seed(dstDay, []);
      await open(t, date: dstDay);
      await pick(
        t,
        const TimeOfDay(hour: 23, minute: 30),
        const TimeOfDay(hour: 3, minute: 0),
      );
      final row = (await edits(t, date: dstDay)).single;
      expect(row['start_ts'], epoch(DateTime.utc(2026, 3, 8, 4, 30)));
      expect(row['end_ts'], epoch(DateTime.utc(2026, 3, 8, 7)));
      expect((row['end_ts'] as int) - (row['start_ts'] as int), 150 * 60);
      expect(app.updates, [dstDay]);
    },
  );
  testWidgets('overlapping a saved manual nap does not count it twice', (
    t,
  ) async {
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: epoch(DateTime(2021, 4, 6, 14)),
      endTs: epoch(DateTime(2021, 4, 6, 14, 30)),
      source: 'manual',
    );
    await open(t);
    await pick(
      t,
      const TimeOfDay(hour: 14, minute: 10),
      const TimeOfDay(hour: 14, minute: 40),
    );
    expect(find.textContaining('overlaps a nap already'), findsOneWidget);
    expect(await edits(t), hasLength(1));
    expect(app.updates, isEmpty);
  });
  testWidgets('refused manual nap save keeps the day editable and retries', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER synthetic_nap_refusal BEFORE INSERT ON sleep_nap BEGIN SELECT RAISE(ABORT,'synthetic nap refusal'); END",
    );
    await open(t);
    await pick(
      t,
      const TimeOfDay(hour: 14, minute: 0),
      const TimeOfDay(hour: 14, minute: 30),
    );
    expect(find.text('The edit could not save. Try again.'), findsOneWidget);
    expect(await edits(t), isEmpty);
    expect(app.updates, isEmpty);
    await t.runAsync(() => db.execute('DROP TRIGGER synthetic_nap_refusal'));
    await pick(
      t,
      const TimeOfDay(hour: 14, minute: 0),
      const TimeOfDay(hour: 14, minute: 30),
    );
    expect(await edits(t), hasLength(1));
    expect(app.updates, [day]);
  });
  testWidgets(
    'refused deletion keeps a manual nap and retries without a suppression',
    (t) async {
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: epoch(DateTime(2021, 4, 6, 14)),
        endTs: epoch(DateTime(2021, 4, 6, 14, 30)),
        source: 'manual',
      );
      await db.execute(
        "CREATE TRIGGER synthetic_nap_refusal BEFORE DELETE ON sleep_nap BEGIN SELECT RAISE(ABORT,'synthetic nap deletion refusal'); END",
      );
      await open(t);
      await tap(t, 'Delete');
      expect(find.text('The edit could not save. Try again.'), findsOneWidget);
      expect((await edits(t)).single['source'], 'manual');
      await t.runAsync(() => db.execute('DROP TRIGGER synthetic_nap_refusal'));
      await tap(t, 'Delete');
      expect(await edits(t), isEmpty);
      expect(app.updates, [day]);
    },
  );
  testWidgets('failed nap reads retain corrections and retry honestly', (
    t,
  ) async {
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: epoch(DateTime(2021, 4, 6, 14)),
      endTs: epoch(DateTime(2021, 4, 6, 14, 30)),
      source: 'manual',
    );
    repo.fail = true;
    await open(t);
    expect(find.text('Naps could not load'), findsOneWidget);
    expect(find.text('No naps on this day'), findsNothing);
    expect(await edits(t), hasLength(1));
    repo.fail = false;
    await tap(t, 'Retry');
    expect(find.textContaining('you logged this'), findsOneWidget);
    expect(app.updates, isEmpty);
  });
  testWidgets('failed restore keeps the rejected detector window until retry', (
    t,
  ) async {
    final s = epoch(DateTime(2021, 4, 6, 14)),
        e = epoch(DateTime(2021, 4, 6, 14, 30));
    await seed(day, [
      {
        'start': s,
        'end': e,
        'duration_min': 30,
        'source': 'detected',
        'confidence': .7,
      },
    ]);
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: s,
      endTs: e,
      source: 'rejected',
    );
    await open(t);
    repo.fail = true;
    await tap(t, 'Put it back');
    expect(find.text('The edit could not save. Try again.'), findsOneWidget);
    expect((await edits(t)).single['source'], 'rejected');
    repo.fail = false;
    await tap(t, 'Put it back');
    expect(await edits(t), isEmpty);
    expect(find.textContaining('asleep · detected'), findsOneWidget);
    expect(app.updates, [day]);
  });
}
