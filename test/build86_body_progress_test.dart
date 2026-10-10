// Body and Progress (build 86): one weight source shared with Food, past or
// imported weights that never move past calorie numbers, tape and import
// parity with AkshatOS Body, and a review that only states what was recorded.
// Synthetic data only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart' show Profile;
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/profile_history.dart';
import 'package:openstrap_edge/data/progress_review.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_body_progress_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  group('one weight source, past calorie numbers fixed', () {
    test('a backdated weight is history only and never prices that day', () async {
      final today = todayLabel();
      final t = DateTime.parse(today);
      final lastWeek = dayLabelOf(DateTime(t.year, t.month, t.day - 7));
      await BodyLogDb.putWeight(lastWeek, 176.4, 'lb');
      final row = (await BodyLogDb.weightOn(lastWeek))!;
      expect(row.historyOnly, isTrue);
      expect(row.entered, 176.4);
      expect(row.unit, 'lb');
      // The day's calculation weight is still the profile's, not the import.
      final priced = await ProfileHistory.on(lastWeek, const Profile(weightKg: 82));
      expect(priced.weightKg, 82);
      // Food's maintenance-from-weight estimate does not see it either.
      final db = await LocalDb.instance;
      expect(await BodyWeight.since(db, lastWeek, calculation: true), isEmpty);
      expect(await BodyWeight.since(db, lastWeek), hasLength(1));
    });

    test("today's weigh-in is a calculation input, as Food's always was", () async {
      final today = todayLabel();
      await BodyLogDb.putWeight(today, 80.5, 'kg');
      expect((await BodyLogDb.weightOn(today))!.historyOnly, isFalse);
      final priced = await ProfileHistory.on(today, const Profile(weightKg: 82));
      expect(priced.weightKg, 80.5);
    });

    test('seven-day mean uses actual readings and says how many', () {
      final rows = [
        for (final (d, kg) in const [('2026-09-01', 80.0), ('2026-09-04', 81.0), ('2026-09-10', 79.0)])
          (date: d, kg: kg, atTs: 0, unit: 'kg', entered: kg, source: 'whoop', originId: null, historyOnly: false),
      ];
      final m = BodyLogDb.sevenDayMean(rows, '2026-09-07')!;
      expect(m.count, 2);
      expect(m.kg, 80.5);
      expect(BodyLogDb.sevenDayMean(rows, '2026-08-20'), isNull);
    });
  });

  group('tape', () {
    test('values are range-checked and rounded; unknown sites survive', () async {
      await BodyLogDb.putMeasure(BodyMeasure(
        date: '2026-09-05',
        recordedAt: DateTime(2026, 9, 5, 8),
        inches: {'waistNavel': 34.123, 'neck': 15.5, 'futureSite': 12},
      ));
      final m = (await BodyLogDb.measures()).first;
      expect(m.value(BodySite.waistNavel), 34.12);
      expect(m.inches['futureSite'], 12);
      expect(
        () => BodyLogDb.putMeasure(BodyMeasure(date: '2026-09-06', recordedAt: DateTime(2026), inches: {'hips': 90})),
        throwsA(isA<BodyLogError>()),
      );
    });

    test('change since the last session that measured that site', () async {
      await BodyLogDb.putMeasure(BodyMeasure(
        date: '2026-09-12',
        recordedAt: DateTime(2026, 9, 12, 8),
        inches: {'waistNavel': 33.62},
      ));
      final all = await BodyLogDb.measures();
      final latest = all.first;
      expect(BodyLogDb.changeSince(all, latest, BodySite.waistNavel), closeTo(-0.5, 1e-9));
      expect(BodyLogDb.changeSince(all, latest, BodySite.neck), isNull);
    });

    test('Navy estimate needs height, waist and neck', () {
      expect(BodyLogDb.navyBodyFat(34, 15.5, null), isNull);
      // 86.010·log10(18.5) − 70.041·log10(73.5) + 36.76 = 15.03
      expect(BodyLogDb.navyBodyFat(34, 15.5, 73.5), closeTo(15.03, 0.01));
    });
  });

  group('imports', () {
    double apple(DateTime d) => d.millisecondsSinceEpoch / 1000 - 978307200;

    test('an AkshatOS Body backup previews, keeps lb, and reports missing photos', () async {
      final manifest = jsonEncode({
        'version': 1,
        'exportedAt': apple(DateTime(2026, 10, 1)),
        'weights': [
          {'id': 'W1', 'day': '2026-08-02', 'pounds': 180.2, 'recordedAt': apple(DateTime(2026, 8, 2, 7))},
          {'id': 'W2', 'day': '2026-09-01', 'pounds': 179.0, 'recordedAt': apple(DateTime(2026, 9, 1, 7))},
        ],
        'measurements': [
          {'id': 'M1', 'day': '2026-08-02', 'recordedAt': apple(DateTime(2026, 8, 2, 7)), 'inches': {'waistNavel': 35.0}},
        ],
        'photos': [
          {'id': 'P1', 'day': '2026-08-02', 'pose': 'front', 'recordedAt': apple(DateTime(2026, 8, 2, 7))},
        ],
        'measurementWeekday': 7,
      });
      // 2026-09-01 already holds a different weight here.
      await BodyLogDb.putWeight('2026-09-01', 70, 'kg');
      final plan = await planBodyImport(manifest);
      expect(plan.weights.single.date, '2026-08-02');
      expect(plan.sameDayConflicts.single.date, '2026-09-01');
      expect(plan.missingPhotoFiles.single.id, 'P1');
      expect(plan.measureWeekday, DateTime.saturday);
      final n = await applyBodyImport(plan, encode: (_) async => const []);
      expect(n, 2);
      final w = (await BodyLogDb.weightOn('2026-08-02'))!;
      expect(w.historyOnly, isTrue);
      expect(w.unit, 'lb');
      expect(w.entered, 180.2);
      expect((await BodyLogDb.weightOn('2026-09-01'))!.kg, 70, reason: 'never overwritten');
      final again = await planBodyImport(manifest);
      expect(again.weights, isEmpty, reason: 'repeating an import is a no-op');
    });

    test('a generated body-history file imports weights only, as history', () async {
      final f = jsonEncode({
        'format': 'whoop-body-history',
        'version': 1,
        'source': 'myfitnesspal-screenshots',
        'weights': [
          {'id': 'mfp:2025-01-05', 'date': '2025-01-05', 'value': 200.4, 'unit': 'lb'},
        ],
      });
      final plan = await planBodyImport(f);
      await applyBodyImport(plan, encode: (_) async => const []);
      final w = (await BodyLogDb.weightOn('2025-01-05'))!;
      expect(w.source, 'myfitnesspal-screenshots');
      expect(w.historyOnly, isTrue);
      expect(await BodyLogDb.measures(), isNot(contains(predicate((m) => (m as BodyMeasure).date == '2025-01-05'))));
    });
  });

  group('review', () {
    test('closed weeks are Monday to Sunday, months use real lengths', () {
      final (last, before) = closedWeeks('2026-10-10'); // a Saturday
      expect(last.from, '2026-09-28');
      expect(last.to, '2026-10-04');
      expect(before.from, '2026-09-21');
      final (m, mb) = closedMonths('2026-03-15');
      expect(m.from, '2026-02-01');
      expect(m.days, 28);
      expect(mb.days, 31);
    });

    test('sparse evidence asks for more instead of a verdict', () {
      final r = review(
        weightBefore: (mean: 80, count: 1, first: null, last: null),
        weightAfter: (mean: 79.6, count: 2, first: null, last: null),
        waistChange: null,
        food: (kcal: null, kcalDays: 0, protein: null, proteinDays: 0, windowDays: 7),
        lifts: const [],
        sessionsAfter: 2,
      );
      expect(r.state, ReviewState.gatherEvidence);
    });

    test('stable weight with stronger comparable lifts is consistent with the goal', () {
      LiftSet s(double l, int r) => LiftSet(reps: r, load: l, completedAt: DateTime(2026));
      final r = review(
        weightBefore: (mean: 80, count: 5, first: null, last: null),
        weightAfter: (mean: 80.1, count: 6, first: null, last: null),
        waistChange: -0.25,
        food: (kcal: 2400, kcalDays: 6, protein: 170, proteinDays: 5, windowDays: 7),
        lifts: [
          (exercise: 'Bench', mode: LiftLoadMode.perHand, before: s(40, 8), after: s(40, 10), direction: 1),
        ],
        sessionsAfter: 4,
      );
      expect(r.state, ReviewState.keepGoing);
      expect(r.because.join(' '), contains('1 of 1 comparable lifts better'));
    });

    test('a range summary carries its real dates; a single reading has no change', () {
      final s = bodySummary([(date: '2026-09-02', value: 34.0)])!;
      expect(s.count, 1);
      expect(s.start.date, '2026-09-02');
      final steps = stepsSummary([(date: '2026-09-01', value: 8000), (date: '2026-09-03', value: 12000)]);
      expect(steps.days, 2);
      expect(steps.average, 10000, reason: 'measured days only, not the calendar span');
    });
  });
}
