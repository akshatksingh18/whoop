// Ordinary short-substrate derivation with an unavailable real session table.
// This checks persistence/recovery, not a complete night or metric calibration.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/data/series_codec.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-partial-read'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  test(
    'COV-48 ordinary thin-input derive retains a richer prior night verbatim',
    () async {
      final ts = localDayStartSec(day)! + 43200;
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'date': day,
          'device_family': 'gen4',
          'scalars': {'rhr': 57.0},
          'wear': {'fraction': .75},
        }),
        windowJson: '{}',
        rhr: 57,
        finalized: false,
        series: {'rhr': 57},
      );
      await LocalDb.insertRecord(
        RawRecord(
          counter: 1,
          packetType: 47,
          hex: 'authored-pruned-night',
          recTs: ts,
          capturedAt: ts * 1000,
        ),
        Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
      );
      final db = await LocalDb.instance;
      final before = await LocalDb.dayResult(day);
      final series = await db.query('metric_series', orderBy: 'date,key');
      final raw = await db.query('decoded_onehz');
      final logs = <String>[];
      final engine = DerivationEngine(background: true, log: logs.add);
      expect(
        await engine.run(const Profile(), force: true),
        1,
        reason: logs.join('\n'),
      );
      expect(
        logs.any(
          (s) =>
              s.contains('sleep-window substrate pruned') &&
              s.contains('kept the existing result'),
        ),
        true,
      );
      expect(
        logs.any((s) => s.contains('second half') && s.contains('failed')),
        false,
      );
      expect(await LocalDb.dayResult(day), before);
      expect(await db.query('metric_series', orderBy: 'date,key'), series);
      expect(await db.query('decoded_onehz'), raw);
      expect(engine.running, false);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
  for (final previous in [
    (kAlgoVersion, false),
    (kAlgoVersion, true),
    (kAlgoVersion - 1, false),
  ]) {
    test(
      'COV-48 ordinary derive retains v${previous.$1} partial=${previous.$2} detail after second-half read failure',
      () async {
        final ts = localDayStartSec(day)! + 43200;
        final periods = {
          'periods': [
            {
              'start': ts - 3600,
              'end': ts - 1800,
              'duration_min': 30,
              'is_main': false,
              'source': 'manual',
            },
          ],
          'total_asleep_min': 30,
        };
        final wear = {'fraction': .75, 'worn_min': 45};
        final curve = [
          {'t': ts - 60, 'v': 70.0},
        ];
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: previous.$1,
          payloadJson: jsonEncode({
            'date': day,
            'device_family': 'gen4',
            'scalars': {'steps': 1200.0},
            'sleep_periods': periods,
            'wear': wear,
            'series': {'hr_curve': curve},
          }),
          windowJson: '{}',
          finalized: false,
          partial: previous.$2,
          series: {'steps': 1200},
        );
        await LocalDb.insertRecord(
          RawRecord(
            counter: 1,
            packetType: 47,
            hex: 'authored-partial-read',
            recTs: ts,
            capturedAt: ts * 1000,
          ),
          Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
        );
        final db = await LocalDb.instance;
        final oldRows = await db.query('day_result', orderBy: 'algo_version');
        final raw = await db.query('decoded_onehz');
        await db.execute(
          'ALTER TABLE sessions RENAME TO authored_hidden_sessions',
        );
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        try {
          expect(
            await engine.run(const Profile(), force: true),
            1,
            reason: logs.join('\n'),
          );
          expect(
            logs.any((s) => s.contains('second half') && s.contains('failed')),
            true,
          );
          expect(logs.any((s) => s.contains('carried the previous')), true);
          final row = (await LocalDb.dayResult(day))!;
          final bundle = SeriesCodec.decodePayloadJson(
            row['payload_json'] as String,
          )!;
          expect(row['algo_version'], kAlgoVersion);
          expect(
            row['partial'],
            previous.$1 == kAlgoVersion && !previous.$2 ? 0 : 1,
          );
          expect(row['finalized'], 0);
          expect(row['skipped'], 0);
          expect(row['rhr'], isNull);
          expect((bundle['scalars'] as Map)['rhr'], isNull);
          expect(bundle['sleep_periods'], periods);
          expect(bundle['wear'], wear);
          expect(
            (bundle['series'] as Map)['hr_curve'],
            [
              {'t': ts, 'v': 60},
            ],
            reason: 'fresh first-half observations outrank a previous curve',
          );
          expect(await db.query('decoded_onehz'), raw);
          if (previous.$1 != kAlgoVersion) {
            expect(
              (await db.query(
                'day_result',
                where: 'algo_version = ?',
                whereArgs: [previous.$1],
              )).single,
              oldRows.single,
            );
          }
          expect(engine.running, false);
        } finally {
          await db.execute(
            'ALTER TABLE authored_hidden_sessions RENAME TO sessions',
          );
        }
        expect(
          await engine.run(const Profile(), force: true),
          1,
          reason: logs.join('\n'),
        );
        final retried = (await LocalDb.dayResult(day))!;
        expect(retried['partial'], 0);
        expect(retried['skipped'], 0);
        expect(retried['finalized'], 0);
        expect(await LocalDb.lastDecodedRecTs(), ts);
        expect(await db.query('decoded_onehz'), raw);
        expect(engine.running, false);
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  }
}
