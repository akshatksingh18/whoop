// The active Steps comparison reads measured days and dated calculation anchors.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/profile_history.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart' show pointsOf;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('step-comparison-provenance'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  final at = DateTime(2021, 4, 6, 9);
  const complete = Profile(ageYears: 30, weightKg: 70, heightCm: 170, sex: 'f');
  int noon(DateTime d) =>
      DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch ~/ 1000;
  Future<void> seed(DateTime date, {int steps = 1000}) async {
    final start = noon(date), end = noon(date) + 3600;
    await LocalDb.replacePhoneCoverageForDay(
      dayLabelOf(date),
      [(startTs: start, endTs: end, steps: steps)],
      distances: {'$start-$end': steps == 0 ? 0 : steps / 2},
    );
  }

  LocalRepositoryImpl repo(Profile p) =>
      LocalRepositoryImpl(getProfileMap: p.toMap);

  for (final (label, profile) in [
    ('missing age', const Profile(weightKg: 70, heightCm: 170, sex: 'f')),
    ('missing height', const Profile(ageYears: 30, weightKg: 70, sex: 'f')),
    ('missing age and height', const Profile(weightKg: 70, sex: 'f')),
    ('complete profile', complete),
  ]) {
    test(
      'COV-61 $label retains measured step components and leaves calculation anchors unchanged',
      () async {
        await seed(at);
        final db = await LocalDb.instance;
        final before = await db.query('live_coverage');
        final result = await stepCalorieModels(
          repo(profile),
          [(t: noon(at), v: 999999)],
          days: 1,
          at: at,
        );
        expect(result.budget.single.t, noon(at));
        expect(result.acsm.single.t, noon(at));
        expect(result.budget.single.v, closeTo(2.74 * 1000 * 70 / 8368, 1e-9));
        expect(result.acsm.single.v, closeTo(.005 * 70 * .1 * 500, 1e-9));
        expect(await db.query('live_coverage'), equals(before));
        expect(await db.query('sessions'), isEmpty);
        expect(await db.query('day_result'), isEmpty);
        expect(await CalculationStore.read(ProfileHistory.key), isNull);
      },
    );
  }
  test(
    'COV-61 missing weight cannot turn a chart point into priced energy',
    () async {
      await seed(at);
      final reader = repo(const Profile(ageYears: 30, heightCm: 170, sex: 'f'));
      final actualChart = pointsOf(await reader.getChart('steps'));
      expect(actualChart.single.v, 1000);
      final result = await stepCalorieModels(
        reader,
        actualChart,
        days: 1,
        at: at,
      );
      expect(result.budget, isEmpty);
      expect(result.acsm, isEmpty);
    },
  );
  test(
    'COV-62 retained Steps without measured coverage cannot become zero comparison calories',
    () async {
      final reader = repo(complete);
      await LocalDb.putMetricSeriesValue(dayLabelOf(at), 'steps', 1000);
      final actualChart = pointsOf(await reader.getChart('steps'));
      expect(actualChart.single.v, 1000);
      final db = await LocalDb.instance;
      final before = await db.query('metric_series');
      final result = await stepCalorieModels(
        reader,
        actualChart,
        days: 1,
        at: at,
      );
      expect(result.budget, isEmpty);
      expect(result.acsm, isEmpty);
      expect(await db.query('metric_series'), before);
      expect(await db.query('live_coverage'), isEmpty);
    },
  );
  test(
    'COV-61 measured zero stays zero with only a known body weight',
    () async {
      await seed(at, steps: 0);
      final result = await stepCalorieModels(
        repo(const Profile(weightKg: 70)),
        [(t: noon(at), v: 500)],
        days: 1,
        at: at,
      );
      expect(result.budget.single.v, 0);
      expect(result.acsm.single.v, 0);
    },
  );
  for (final days in [-1, 0, 1, 365, 9999]) {
    test(
      'COV-61 comparison range $days retains calendar boundaries and excludes future rows',
      () async {
        final dates = [
          for (final offset in [-365, -364, -1, 0, 1])
            DateTime(at.year, at.month, at.day + offset),
        ];
        for (final date in dates) {
          await seed(date);
        }
        final result = await stepCalorieModels(
          repo(complete),
          [for (final date in dates) (t: noon(date), v: 1)],
          days: days,
          at: at,
        );
        final expected = days <= 1
            ? [noon(at)]
            : dates.skip(1).take(3).map(noon).toList();
        expect(result.budget.map((p) => p.t), expected);
        expect(result.acsm.map((p) => p.t), expected);
        expect(
          await (await LocalDb.instance).query('live_coverage'),
          hasLength(5),
        );
      },
    );
  }
  test(
    'COV-61 a dated calculation weight wins over the current profile and history-only measurement',
    () async {
      await seed(at);
      final baseline = {...complete.toMap(), 'weight_kg': 50};
      await CalculationStore.write(
        ProfileHistory.key,
        jsonEncode({'baseline': baseline}),
      );
      final db = await LocalDb.instance;
      await db.insert('body_weight', {
        'date': dayLabelOf(at),
        'kg': 90,
        'at_ts': noon(at),
        'source': 'authored import',
        'history_only': 1,
      });
      final anchors = await CalculationStore.read(ProfileHistory.key);
      final measurements = await db.query('body_weight');
      final result = await stepCalorieModels(
        repo(complete),
        [(t: noon(at), v: 1000)],
        days: 1,
        at: at,
      );
      expect(result.budget.single.v, closeTo(2.74 * 1000 * 50 / 8368, 1e-9));
      expect(result.acsm.single.v, closeTo(.005 * 50 * .1 * 500, 1e-9));
      expect(await CalculationStore.read(ProfileHistory.key), anchors);
      expect(await db.query('body_weight'), measurements);
      expect(LocalDb.debugBandSteps, false);
    },
  );
}
