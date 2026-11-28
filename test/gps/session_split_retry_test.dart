// Real stored-session re-score + protocol-decoded pulse + synthetic GPS only.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_models.dart';
import '../compute/prepare_handoff_test.dart' show raw;
import '../support/coverage_store.dart';
import '../support/store_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('split-freeze-retry'));
  setUp(resetCoverageStore);
  tearDown(
    () async => (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_split_refusal',
    ),
  );
  tearDownAll(LocalDb.close);
  for (final altitude in [false, true]) {
    for (final refuse in [false, true]) {
      test(
        'real split freeze altitude=$altitude refusal=$refuse preserves data and retries',
        () async {
          const ts = 1760004000, id = 'authored-split-session';
          final db = await LocalDb.instance;
          final raws = <RawRecord>[], samples = <Sample?>[];
          for (var i = 0; i < 240; i++) {
            final bytes = p.hexToBytes(raw(ts + i, 140));
            ByteData.sublistView(bytes).setUint32(3, i + 1, Endian.little);
            final decoded = p.parseR24(bytes)!;
            raws.add(
              RawRecord(
                counter: decoded.counter,
                packetType: 47,
                hex: bytes
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(),
                capturedAt: (ts + i) * 1000,
                recTs: ts + i,
              ),
            );
            samples.add(
              Sample(
                tsEpoch: decoded.tsEpoch,
                counter: decoded.counter,
                hr: decoded.hr,
                rrIntervalsMs: decoded.rrIntervalsMs,
                ax: decoded.accelG[0],
                ay: decoded.accelG[1],
                az: decoded.accelG[2],
              ),
            );
          }
          await SyncLedgerStore.commitBatch(
            raws,
            samples,
            deviceFamily: 'gen4',
          );
          await SessionStore.put({
            'id': id,
            'start_ts': ts,
            'end_ts': ts + 240,
            'type': 'running',
            'status': 'done',
            'source': 'band',
            'device_family': 'gen4',
            'trace_samples': 0,
            'created_at': 1,
          });
          await WorkoutRouteStore.appendPoints(id, [
            for (var i = 0; i <= 240; i++)
              RoutePoint(
                seq: i,
                tsMs: (ts + i) * 1000,
                lat: 0,
                lng: i * .00004,
                accuracy: 3,
                speed: 4.4,
                alt: altitude ? 20 + i * .02 : null,
              ).toRow(id),
          ]);
          final frames = await db.query('decoded_onehz');
          final route = await WorkoutRouteStore.points(id);
          await WorkoutRouteStore.putSplits(id, [
            {
              'km': 1,
              'meters': 800.0,
              'duration_sec': 240,
              'avg_hr': 130.0,
              'net_elev_m': null,
            },
          ]);
          final old = await splitRows(id);
          if (refuse) {
            await db.execute(
              "CREATE TRIGGER authored_split_refusal BEFORE INSERT ON workout_split BEGIN SELECT RAISE(ABORT,'authored split write refusal'); END",
            );
          }
          final repo = LocalRepositoryImpl(
            getProfileMap: () => {
              'age': 30,
              'sex': 'f',
              'weight_kg': 70.0,
              'height_cm': 170.0,
              'resting_hr': 60,
            },
          );
          final first = await repo.getWorkout(id);
          expect(first['workout_id'] ?? first['id'], id);
          if (refuse) {
            expect(await splitRows(id), old);
            await db.execute('DROP TRIGGER authored_split_refusal');
            await repo.getWorkout(id);
          }
          final frozen = await splitRows(id);
          expect(
            frozen,
            hasLength(2),
            reason:
                'A transient failed freeze must retry while its actual inputs still exist',
          );
          expect(frozen.first['meters'], closeTo(1000, .01));
          expect(frozen.first['avg_hr'], closeTo(140, .01));
          expect(
            frozen.first['net_elev_m'],
            altitude ? greaterThan(0) : isNull,
          );
          expect(await db.query('decoded_onehz'), frames);
          expect(await WorkoutRouteStore.points(id), route);
          expect(await db.query('day_result'), isEmpty);
        },
      );
    }
  }
}
