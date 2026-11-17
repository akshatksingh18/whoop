// Tiny real SQLite inputs: retention after scope selection, before the next day.
// No complete-night work, private capture, clock override or production seam.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-concurrent-retention'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const older = '2021-04-06', newer = '2021-04-07';
  final historyWindows = <String, String>{
    'absent': jsonEncode({'value': '—'}),
    'missing endpoint': jsonEncode({
      'value': {'onset_ms': 100000},
    }),
    'reversed endpoints': jsonEncode({
      'value': {'onset_ms': 200000, 'offset_ms': 100000},
    }),
    'malformed JSON': '{',
    'wrong endpoint type': jsonEncode({
      'value': {'onset_ms': 'damaged', 'offset_ms': 200000},
    }),
  };
  for (final entry in historyWindows.entries) {
    test(
      'COV-48 ${entry.key} history cannot erase a richer saved night',
      () async {
        final ts = localDayStartSec(newer)! + 43200;
        for (final day in [older, newer]) {
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'date': day,
              'device_family': 'gen4',
              'scalars': {'rhr': 57.0},
              'wear': {'fraction': .75},
            }),
            windowJson: day == older ? entry.value : '{}',
            rhr: 57,
            finalized: day == older,
            series: {'rhr': 57},
          );
        }
        await LocalDb.insertRecord(
          RawRecord(
            counter: 1,
            packetType: 47,
            hex: 'authored-window-recovery',
            recTs: ts,
            capturedAt: ts * 1000,
          ),
          Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
        );
        final db = await LocalDb.instance;
        final days = await db.query('day_result', orderBy: 'day_id');
        final series = await db.query('metric_series', orderBy: 'date,key');
        final versions = await db.query(
          'metric_series_version',
          orderBy: 'date',
        );
        final raw = await db.query('decoded_onehz');
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        for (var attempt = 0; attempt < 2; attempt++) {
          expect(
            await engine.run(const Profile(), force: true),
            1,
            reason: logs.join('\n'),
          );
          expect(engine.running, false);
          expect(engine.snapshot()['active_days'], isEmpty);
          expect(await db.query('day_result', orderBy: 'day_id'), days);
          expect(await db.query('metric_series', orderBy: 'date,key'), series);
          expect(
            await db.query('metric_series_version', orderBy: 'date'),
            versions,
          );
          expect(await db.query('decoded_onehz'), raw);
        }
        final shouldReport =
            entry.key == 'malformed JSON' || entry.key == 'wrong endpoint type';
        expect(
          logs.any(
            (s) =>
                s.contains('sleep history for midsleep prior FAILED/skipped'),
          ),
          shouldReport,
          reason: logs.join('\n'),
        );
        expect(logs.any((s) => s.contains('kept the existing result')), true);
        expect(
          logs.any((s) => s.contains('derive day $newer FAILED/skipped')),
          false,
        );
      },
    );
  }
  for (final source in ['manual', 'confirmed', 'nap']) {
    test(
      'COV-48 scoped $source day retains its real result when raw is pruned before prepare',
      () async {
        final db = await LocalDb.instance;
        final start = localDayStartSec(older)!;
        for (final (index, day) in [(1, older), (2, newer)]) {
          final ts = localDayStartSec(day)! + 43200;
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'date': day,
              'device_family': 'gen4',
              'scalars': {'rhr': 55.0 + index},
              'wear': {'fraction': .75},
            }),
            windowJson: jsonEncode({
              'value': {
                'onset_ms': (localDayStartSec(day)! + 3600) * 1000,
                'offset_ms': (localDayStartSec(day)! + 3 * 3600) * 1000,
              },
            }),
            rhr: 55.0 + index,
            finalized: day == older,
            series: {'rhr': 55.0 + index},
          );
          await LocalDb.insertRecord(
            RawRecord(
              counter: index,
              packetType: 47,
              hex: 'authored-retention-$source-$day',
              recTs: ts,
              capturedAt: ts * 1000,
            ),
            Sample(tsEpoch: ts, counter: index, hr: 60, ax: 0, ay: 0, az: 1),
          );
        }
        if (source == 'nap') {
          await LocalDb.putNapEdit(
            dayId: older,
            startTs: start + 13 * 3600,
            endTs: start + 14 * 3600,
            source: 'manual',
          );
        } else {
          await LocalDb.putSleepOverride(
            dayId: older,
            onsetTs: start + 3600,
            offsetTs: start + 3 * 3600,
            source: source,
          );
        }
        final saved = await LocalDb.dayResult(older);
        final series = await db.query(
          'metric_series',
          where: 'date = ?',
          whereArgs: [older],
          orderBy: 'key',
        );
        final versions = await db.query(
          'metric_series_version',
          where: 'date = ?',
          whereArgs: [older],
        );
        final overrides = await db.query('sleep_override');
        final naps = await db.query('sleep_nap');
        final logs = <String>[], completed = <String>[];
        late Future<int> prune;
        var pruned = false;
        final engine = DerivationEngine(background: true, log: logs.add);
        final count = await engine.run(
          const Profile(),
          heavy: true,
          force: true,
          onDayDone: (day, index, total) {
            completed.add(day);
            expect(total, 2);
            if (day == newer) {
              // The actual progress callback coordinates an independent retention
              // write. SQLite queues it before the next sequential lane's reads.
              pruned = true;
              prune = db.delete(
                'decoded_onehz',
                where: 'rec_ts >= ? AND rec_ts < ?',
                whereArgs: [start, localDayStartSec(newer)!],
              );
            }
          },
        );
        expect(pruned, true);
        expect(await prune, 1);
        expect(count, 1, reason: logs.join('\n'));
        expect(completed, [newer, older]);
        expect(
          logs.any(
            (s) => s.contains(
              'derive day $older skipped: override day, raw pruned — kept',
            ),
          ),
          true,
          reason: logs.join('\n'),
        );
        expect(engine.snapshot()['concurrency'], 1);
        expect(engine.running, false);
        expect(engine.snapshot()['active_days'], isEmpty);
        expect(await LocalDb.dayResult(older), saved);
        expect(
          await db.query(
            'metric_series',
            where: 'date = ?',
            whereArgs: [older],
            orderBy: 'key',
          ),
          series,
        );
        expect(
          await db.query(
            'metric_series_version',
            where: 'date = ?',
            whereArgs: [older],
          ),
          versions,
        );
        expect(await db.query('sleep_override'), overrides);
        expect(await db.query('sleep_nap'), naps);
        expect(
          await db.query(
            'decoded_onehz',
            where: 'rec_ts < ?',
            whereArgs: [localDayStartSec(newer)!],
          ),
          isEmpty,
        );
        // An ordinary repeat cannot regenerate pruned bytes or erase the result.
        expect(await engine.run(const Profile(), heavy: true), 1);
        expect(await LocalDb.dayResult(older), saved);
        expect(await db.query('sleep_override'), overrides);
        expect(await db.query('sleep_nap'), naps);
      },
    );
  }
}
