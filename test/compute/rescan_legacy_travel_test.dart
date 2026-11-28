import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('rescan-legacy-travel'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final jump in [-180, 180]) {
    test(
      'rescan leaves a changed baseline pending during a legacy ${jump.abs()} minute timezone jump ($jump)',
      () async {
        const day = '2021-04-06';
        const previousSignature = 'authored-prior-baseline';
        expect(DayClock.days, isEmpty);
        final nowOffset = DateTime.now().timeZoneOffset.inMinutes;
        await CursorStore.write('baseline_sig', previousSignature);
        await MetricSeriesStore.putBaseline(
          'tz_travel_guard',
          jsonEncode({'offset_min': nowOffset + jump}),
        );
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson: '{"scalars":{"rhr":57}}',
          windowJson: '{}',
          finalized: true,
          rhr: 57,
          series: const {'rhr': 57},
        );
        final timestamp = localDayStartSec(day)! + 12 * 3600;
        final db = await LocalDb.instance;
        await db.insert('decoded_onehz', {
          'device_id': '',
          'ts_ms': timestamp * 1000,
          'rec_ts': timestamp,
          'counter': 1,
          'hr': 65,
          'device_family': 'gen4',
        });
        final guard = await MetricSeriesStore.baseline('tz_travel_guard');
        final result = await LocalDb.dayResult(day);
        final samples = await db.query('decoded_onehz');
        final series = await db.query('metric_series');
        final logs = <String>[];
        final completed = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        for (var pass = 0; pass < 2; pass++) {
          final count = await engine.rescanRecent(
            const Profile(),
            onDayDone: (day, _, _) => completed.add(day),
          );
          expect(count, 0);
          expect(engine.running, isFalse);
          expect(await CursorStore.read('baseline_sig'), previousSignature);
          expect(await MetricSeriesStore.baseline('tz_travel_guard'), guard);
          expect(await LocalDb.dayResult(day), result);
          expect(await db.query('decoded_onehz'), samples);
          expect(await db.query('metric_series'), series);
        }
        expect(completed, isEmpty);
        expect(
          logs.where(
            (message) => message.contains('rescan: possible timezone change'),
          ),
          hasLength(2),
        );
      },
    );
  }
}
