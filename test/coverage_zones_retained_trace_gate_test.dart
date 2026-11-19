// Real retained workout rows -> the shipped Zones reader. Missing old traces
// and an accumulating live session never become measured training minutes.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';

import 'support/coverage_store.dart';

Future<void> _anchors() async {
  await LocalDb.putDayResult(
    dayId: todayLabel(),
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode({'device_family': 'gen4'}),
    windowJson: '{}',
    finalized: true,
  );
  await LocalDb.putMetricSeriesValue(todayLabel(), 'hr_ceiling_bpm', 196);
  // Fifteen real stored nights, deliberately asymmetric: median=50, mean=58.
  // The reader must describe the same median anchor the zone method uses.
  for (var i = 0; i < 15; i++) {
    await LocalDb.putMetricSeriesValue(
      todayLabel(DateTime.now().subtract(Duration(days: i))),
      'rhr',
      i < 6
          ? 40
          : i < 9
          ? 50
          : 80,
    );
  }
}

Future<void> _session(
  int index, {
  bool traced = true,
  bool live = false,
}) async {
  final start =
      DateTime.now().millisecondsSinceEpoch ~/ 1000 -
      (live ? 3600 : (index + 1) * 86400);
  await LocalDb.putSession({
    'id': 'retained-zone-$index',
    'start_ts': start,
    'end_ts': live ? null : start + 3000,
    'status': live ? 'live' : 'done',
    'type': 'running',
    'device_family': 'gen4',
    'created_at': start * 1000,
    if (traced)
      'trace_json': jsonEncode({
        'hr': [
          for (var m = 0; m < 40; m++) {'t': m * 60, 'v': 128},
          for (var m = 40; m < 50; m++) {'t': m * 60, 'v': 185},
        ],
      }),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('zones-retained-trace-gate'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  final repo = LocalRepositoryImpl(getProfileMap: () => {'age': 30});
  for (final traced in [7, 8, 9]) {
    for (final legacy in [0, 1, 3]) {
      test(
        '$traced traced and $legacy pre-trace sessions keep the measured gate',
        () async {
          await _anchors();
          for (var i = 0; i < traced + legacy; i++) {
            await _session(i, traced: i < traced);
          }
          final before = await LocalDb.sessionsInRange(0, 1 << 40);
          final result = await repo.getZones();
          expect(result['source'], 'karvonen');
          expect(result['resting_days'], 15);
          expect(result['resting_hr'], 50);
          expect(result['max_hr'], 196);
          expect((result['zones'] as List).first, containsPair('lo', 123));
          final distribution = result['distribution'] as Map?;
          if (traced < 8) {
            expect(
              distribution,
              isNull,
              reason:
                  'untraced history cannot satisfy the measured-sessions gate',
            );
            expect((result['absent'] as Map)['distribution'], isNotNull);
          } else {
            expect(distribution, containsPair('sessions', traced));
            expect(
              distribution,
              containsPair('sessions_without_trace', legacy),
            );
            expect(distribution!['minutes'], [
              40 * traced,
              0,
              0,
              0,
              10 * traced,
            ]);
            expect(distribution['easy_min'], 40 * traced);
            expect(distribution['moderate_min'], 0);
            expect(distribution['hard_min'], 10 * traced);
            expect(distribution['shape'], 'polarised');
            expect(
              (result['absent'] as Map).containsKey('distribution'),
              false,
            );
          }
          expect(await LocalDb.sessionsInRange(0, 1 << 40), before);
          expect(
            await LocalDb.lastDecodedRecTs(),
            isNull,
            reason: 'these retained rows have outlived raw retention',
          );
        },
      );
    }
  }
  for (final traced in [7, 8, 9]) {
    test(
      'a live session is excluded beside $traced completed traced sessions',
      () async {
        await _anchors();
        for (var i = 0; i < traced; i++) {
          await _session(i);
        }
        await _session(20, live: true);
        final live = await LocalDb.session('retained-zone-20');
        final result = await repo.getZones();
        final distribution = result['distribution'] as Map?;
        if (traced < 8) {
          expect(distribution, isNull);
        } else {
          expect(distribution!['sessions'], traced);
          expect(distribution['sessions_without_trace'], 0);
          expect(distribution['easy_min'], traced * 40);
          expect(distribution['hard_min'], traced * 10);
        }
        expect(
          await LocalDb.session('retained-zone-20'),
          live,
          reason:
              'opening Zones must not score or end the accumulating session',
        );
      },
    );
  }
}
