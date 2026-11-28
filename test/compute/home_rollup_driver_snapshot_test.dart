// Today reads genuine rollup envelopes and keeps the stale-data gate.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/crossday_pipeline.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('home-rollup-driver-snapshot'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'Today reads fresh authored drivers and withholds them after the rollup expires',
    () async {
      final today = DateTime.parse(todayLabel());
      String date(int earlier) =>
          dayLabelOf(DateTime(today.year, today.month, today.day - earlier));
      final rollup = buildCrossDayBundle([
        for (var earlier = 35; earlier >= 0; earlier--)
          {
            'date': date(earlier),
            'rhr': earlier == 0 ? 74.0 : 50.0 + earlier % 5,
            'rmssd': earlier == 0 ? 62.0 : 38.0 + earlier % 5,
            'readiness': 70.0,
            'tst_min': 430.0,
          },
      ], {});
      final glassbox = rollup['readiness_glassbox'] as Map;
      final drivers = glassbox['drivers'] as List;
      expect(drivers.map((d) => d['label']), contains('rhr'));
      expect(drivers.map((d) => d['label']), contains('hrv'));
      final current = {
        ...rollup,
        'algo_version': kAlgoVersion,
        'built_for_day': date(0),
      };
      final repo = LocalRepositoryImpl(getProfileMap: () => {});
      final snapshot = jsonEncode(current);
      await MetricSeriesStore.putBaseline('crossday', snapshot);
      final fresh = await HomeData.load(repo);
      expect(fresh.drivers, drivers);
      expect(
        (await MetricSeriesStore.baseline('crossday'))!['payload_json'],
        snapshot,
      );

      final stale = jsonEncode({...current, 'built_for_day': date(40)});
      await MetricSeriesStore.putBaseline('crossday', stale);
      final outdated = await HomeData.load(repo, null, fresh);
      expect(outdated.insightsStale?['kind'], 'stale');
      expect(outdated.drivers, isEmpty);
      expect(
        (await MetricSeriesStore.baseline('crossday'))!['payload_json'],
        stale,
      );
    },
  );
}
