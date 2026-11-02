// Approved historical date selection, using authored charts and the real reader.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/nightly_sweep.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'coverage_what_changed_reader_boundaries_test.dart'
    show ChartRepo, authoredEpoch;

class Breaks extends ChartRepo {
  Breaks(this.boundaries);
  final List<Map<String, Object>> boundaries;
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {
    ...await super.getChart(metric, from: from, to: to),
    'algo_breaks': boundaries,
  };
}

void main() {
  setUp(() => DayClock.install([], []));
  tearDown(() => DayClock.install([], []));
  test(
    'COV-48 future algorithm break retains earlier historical evidence',
    () async {
      final repo = ChartRepo()..breakIndex = 21;
      final before = await repo.getChart('resting_hr');
      final data = await WhatChangedData.load(repo, want: '2021-04-06');
      expect(data.day, '2021-04-06');
      expect(data.longestHistory, 20);
      expect(data.hadToday, true);
      expect(data.findings, hasLength(1));
      expect(data.findings.single.key, 'rhr');
      expect(data.findings.single.text, contains('100'));
      expect(data.findings.single.text, isNot(contains('200')));
      expect(data.grid, hasLength(3));
      expect(data.days, ['2021-04-07', '2021-04-06', '2021-04-05']);
      expect(await repo.getChart('resting_hr'), before);
    },
  );
  test(
    'COV-48 same-day midday algorithm break still excludes older versions',
    () async {
      final data = await WhatChangedData.load(
        ChartRepo()..breakIndex = 20,
        want: '2021-04-06',
      );
      expect(data.hadToday, true);
      expect(data.longestHistory, 0);
      expect(data.findings, isEmpty);
    },
  );
  test(
    'COV-48 unordered breaks choose latest eligible and keep global metadata',
    () async {
      final repo = Breaks([
        for (final i in [21, 5, 10, 2]) {'t': authoredEpoch(i)},
      ]);
      final before = await repo.getChart('resting_hr');
      final series = await collectSweepSeries(repo, DateTime(2021, 4, 6));
      final rhr = series.singleWhere((s) => s.key == 'rhr');
      expect(rhr.today, 100);
      expect(rhr.history, [for (var i = 10; i < 20; i++) 50.0 + (i % 2) * 2]);
      expect(sweepFindings(series), isEmpty);
      expect(await repo.getChart('resting_hr'), before);
    },
  );
  test(
    'COV-48 eligible break keeps its exact epoch cutoff within the day',
    () async {
      final repo = Breaks([
        {'t': authoredEpoch(10) + 1},
      ]);
      final series = await collectSweepSeries(repo, DateTime(2021, 4, 6));
      final rhr = series.singleWhere((s) => s.key == 'rhr');
      expect(rhr.history, [for (var i = 11; i < 20; i++) 50.0 + (i % 2) * 2]);
      expect(rhr.today, 100);
      expect(sweepFindings(series), isEmpty);
    },
  );
  test(
    'COV-48 earlier ordinary day retains its own history after future break',
    () async {
      final data = await WhatChangedData.load(
        ChartRepo()..breakIndex = 21,
        want: '2021-04-05',
      );
      expect(data.day, '2021-04-05');
      expect(data.longestHistory, 19);
      expect(data.hadToday, true);
      expect(data.findings, isEmpty);
    },
  );
  test(
    'COV-48 recorded travel-day assignment determines future break eligibility',
    () async {
      final from = authoredEpoch(0) - 2 * 86400,
          to = authoredEpoch(21) + 3 * 86400;
      final changes = [ZoneChange(from, 'Asia/Kolkata')];
      DayClock.install(
        buildDayZones(fromSec: from, throughSec: to, changes: changes),
        changes,
      );
      final breakAt = DateTime.utc(2021, 4, 6, 20);
      expect(dayLabelAt(breakAt), '2021-04-07');
      final repo = Breaks([
        {'t': breakAt.millisecondsSinceEpoch ~/ 1000},
      ]);
      final data = await WhatChangedData.load(repo, want: '2021-04-06');
      expect(data.day, '2021-04-06');
      expect(data.longestHistory, 20);
      expect(data.findings, hasLength(1));
      expect(data.findings.single.text, isNot(contains('200')));
    },
  );
}
