// Authored chart snapshots exercise the real historical What-changed reader.
// Future observations cannot become history or a finding for an earlier day.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'package:whoop_companion/ui2/screens/month_grid.dart' show kGridMetrics;

DateTime authoredDay(int index) => DateTime(2021, 4, 6 + index - 20, 12);
int authoredEpoch(int index) =>
    authoredDay(index).millisecondsSinceEpoch ~/ 1000;

class ChartRepo extends LocalRepository {
  bool empty = false;
  int? breakIndex;
  @override
  Future<List<String>> availableDays() async => empty
      ? []
      : [
          dayLabelOf(authoredDay(21)),
          dayLabelOf(authoredDay(20)),
          dayLabelOf(authoredDay(19)),
        ];
  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {if (!empty) 'today_day': dayLabelOf(authoredDay(20))},
  };
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {
    'points': metric != 'resting_hr' || empty
        ? []
        : [
            for (var i = 0; i <= 21; i++)
              {
                't': authoredEpoch(i),
                'v': i == 20
                    ? 100
                    : i == 21
                    ? 200
                    : 50 + (i % 2) * 2,
              },
          ],
    'algo_breaks': [
      if (breakIndex case final index?) {'t': authoredEpoch(index)},
    ],
  };
}

void main() {
  setUp(() => DayClock.install([], []));
  tearDown(() => DayClock.install([], []));
  test(
    'empty available history retains the grid and an honest missing day',
    () async {
      final data = await WhatChangedData.load(ChartRepo()..empty = true);
      expect(data.day, isNull);
      expect(data.days, isEmpty);
      expect(data.grid, hasLength(kGridMetrics.length));
      expect(data.findings, isEmpty);
      expect(data.longestHistory, 0);
      expect(data.hadToday, false);
    },
  );
  test(
    'the status day is judged only against its twenty earlier observations',
    () async {
      final data = await WhatChangedData.load(ChartRepo());
      expect(data.day, '2021-04-06');
      expect(data.longestHistory, 20);
      expect(data.hadToday, true);
      expect(data.findings, hasLength(1));
      expect(data.findings.single.key, 'rhr');
      expect(data.findings.single.high, true);
      expect(data.findings.single.text, contains('100'));
      expect(data.findings.single.text, isNot(contains('200')));
    },
  );
  test('an explicit historical day precedes both later outliers', () async {
    final data = await WhatChangedData.load(ChartRepo(), want: '2021-04-05');
    expect(data.day, '2021-04-05');
    expect(data.longestHistory, 19);
    expect(data.hadToday, true);
    expect(data.findings, isEmpty);
    expect(data.days, contains('2021-04-07'));
  });
  test(
    'a preceding algorithm boundary keeps short history from claiming a finding',
    () async {
      final data = await WhatChangedData.load(ChartRepo()..breakIndex = 10);
      expect(data.day, '2021-04-06');
      expect(data.longestHistory, 10);
      expect(data.hadToday, true);
      expect(data.findings, isEmpty);
    },
  );
}
