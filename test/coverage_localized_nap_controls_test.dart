// Shipped nap copy and correction actions against authored, isolated SQLite rows.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/screens/naps.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nap_actions_test.dart' show App, Repo, day, epoch, flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  late Repo repo;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('localized-nap-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    repo = Repo();
    app = App()..repo = repo;
  });
  tearDown(() async {
    final db = await LocalDb.instance;
    await db.execute('DROP TRIGGER IF EXISTS synthetic_nap_refusal');
    app.dispose();
  });
  tearDownAll(LocalDb.close);
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
  Future<void> open(WidgetTester t) async {
    await localizedPage(t, const NapsScreen(day: day), app: app);
    await flush(t);
  }

  Future<void> tap(WidgetTester t, String text) async {
    final f = find.text(text);
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  Future<void> pick(WidgetTester t, int minute) async {
    await tap(t, 'Log a nap');
    expect(find.text('WHEN YOU FELL ASLEEP'), findsOneWidget);
    Navigator.of(
      t.element(find.byType(TimePickerDialog)),
    ).pop(const TimeOfDay(hour: 14, minute: 0));
    await flush(t);
    expect(find.text('WHEN YOU WOKE UP'), findsOneWidget);
    Navigator.of(
      t.element(find.byType(TimePickerDialog)),
    ).pop(TimeOfDay(hour: 14, minute: minute));
    await flush(t);
  }

  testWidgets('a day without a detector answer never claims measured no naps', (
    t,
  ) async {
    await open(t);
    expect(find.text('No nap reading for this day'), findsOneWidget);
    expect(find.text('No naps on this day'), findsNothing);
    expect(find.textContaining('does not have enough of it'), findsOneWidget);
    expect(find.text('Log a nap'), findsOneWidget);
  });
  testWidgets(
    'day navigation loads the selected answer rather than the latest answer',
    (t) async {
      await seed(day, []);
      await seed('2021-04-05', [
        {
          'start': epoch(DateTime(2021, 4, 5, 14)),
          'end': epoch(DateTime(2021, 4, 5, 14, 30)),
          'duration_min': 30,
          'source': 'detected',
        },
      ]);
      await open(t);
      expect(find.text('No naps on this day'), findsOneWidget);
      final previous = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Previous day',
      );
      await t.tap(previous);
      await flush(t);
      expect(find.text('30m asleep · detected'), findsOneWidget);
      expect(find.textContaining('counts toward tonight'), findsOneWidget);
      expect(find.text('No naps on this day'), findsNothing);
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Next day',
        ),
      );
      await flush(t);
      expect(find.text('No naps on this day'), findsOneWidget);
      expect(app.updates, isEmpty);
    },
  );
  testWidgets(
    'detected and manual naps retain separate correction and removal actions',
    (t) async {
      final s = epoch(DateTime(2021, 4, 6, 14));
      await seed(day, [
        {'start': s, 'end': s + 1800, 'duration_min': 30, 'source': 'detected'},
      ]);
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: s + 7200,
        endTs: s + 8400,
        source: 'manual',
      );
      await open(t);
      expect(find.text('30m asleep · detected'), findsOneWidget);
      expect(find.text('20m · you logged this'), findsOneWidget);
      expect(find.textContaining('50m of nap'), findsOneWidget);
      await tap(t, 'Not a nap');
      expect(find.text('Removed'), findsOneWidget);
      expect(
        find.textContaining('removal is kept as a window'),
        findsOneWidget,
      );
      expect(find.text('20m · you logged this'), findsOneWidget);
      expect(
        (await t.runAsync(
          () => LocalDb.napEdits(day),
        ))!.map((e) => e['source']),
        containsAll(['manual', 'rejected']),
      );
      await tap(t, 'Put it back');
      expect(find.text('30m asleep · detected'), findsOneWidget);
      expect(find.text('Removed'), findsNothing);
      await tap(t, 'Delete');
      expect(find.text('20m · you logged this'), findsNothing);
      expect((await t.runAsync(() => LocalDb.napEdits(day)))!, isEmpty);
      expect(app.updates, [day, day, day]);
    },
  );
  testWidgets(
    'restoring an old removal without a proposal is an honest manual report',
    (t) async {
      await seed(day, []);
      final s = epoch(DateTime(2021, 4, 6, 14));
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: s,
        endTs: s + 1800,
        source: 'rejected',
      );
      await open(t);
      final db = await LocalDb.instance;
      await db.execute(
        "CREATE TRIGGER synthetic_nap_refusal BEFORE INSERT ON sleep_nap BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
      );
      await tap(t, 'Put it back');
      expect(find.text('That has not been applied'), findsOneWidget);
      expect(
        (await t.runAsync(() => LocalDb.napEdits(day)))!.single['source'],
        'rejected',
      );
      await t.runAsync(() => db.execute('DROP TRIGGER synthetic_nap_refusal'));
      await tap(t, 'Put it back');
      expect(find.text('30m · you logged this'), findsOneWidget);
      expect(find.text('30m asleep · detected'), findsNothing);
      final row = (await t.runAsync(() => repo.getDayNaps(day)))!;
      expect((row['naps'] as List).single['confidence'], isNull);
      expect(app.updates, [day]);
    },
  );
  testWidgets(
    'localized invalid and overlapping nap windows never write a second nap',
    (t) async {
      await seed(day, []);
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: epoch(DateTime(2021, 4, 6, 14)),
        endTs: epoch(DateTime(2021, 4, 6, 14, 30)),
        source: 'manual',
      );
      await open(t);
      await pick(t, 4);
      expect(
        find.textContaining('between 5 minutes and 6 hours'),
        findsOneWidget,
      );
      await pick(t, 40);
      expect(find.textContaining('overlaps a nap already'), findsOneWidget);
      expect((await t.runAsync(() => LocalDb.napEdits(day)))!, hasLength(1));
      expect(app.updates, isEmpty);
    },
  );
  testWidgets('saved correction exposes a separate recalculation retry state', (
    t,
  ) async {
    await seed(day, []);
    app.napRebuildMessage = 'Synthetic pending recalculation';
    await open(t);
    expect(find.text('Nap edit saved'), findsOneWidget);
    await tap(t, 'Retry update');
    expect(app.updates, [day]);
    app.napRebuilding = true;
    app.notifyListeners();
    await flush(t);
    expect(find.text('Updating sleep calculations'), findsOneWidget);
    expect(find.text('Retry update'), findsNothing);
  });
}
