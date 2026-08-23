// Beat timestamps: the anchor the strap has always sent, and the one
// assumption placed on top of it.
//
// `rr_ts_ms` is `rec_ts * 1000` and stays that way — every beat inside one
// second shares a millisecond, which for two beats 800 ms apart is not a
// rounding error but a false statement. `beat_ts_ms` lands beside it. The
// split is deliberate: the sub-second these are built from was never stored,
// so it cannot be recovered for a row already on disk, and redefining the old
// column would leave two different quantities living in it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/substrate.dart' show beatTimesMs;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

void main() {
  group('beatTimesMs', () {
    test('no sub-second means no beat time — never a whole second instead', () {
      // The state of every row written before this column existed. NULL says
      // "we did not keep it"; rec_ts * 1000 would say "the beat was here".
      expect(beatTimesMs(1000, null, [800, 810]), [null, null]);
    });

    test('the anchor is the strap sub-second, not a rounded second', () {
      // 16384 ticks = exactly half a second on the 32 kHz RTC.
      expect(beatTimesMs(1000, 16384, [800]), [1000500]);
      expect(beatTimesMs(1000, 0, [800]), [1000000]);
      // A tick is ~30 us, so the conversion floors rather than pretending to
      // resolve below a millisecond.
      expect(beatTimesMs(1000, 1, [800]), [1000000]);
      expect(beatTimesMs(1000, 32767, [800]), [1000999]);
    });

    test('beats are spaced by their own intervals, walking backwards', () {
      // The last beat sits at the anchor; each earlier one is the interval
      // after it away. Backwards is the only direction that cannot place a beat
      // AFTER the moment the strap told us about it.
      expect(
        beatTimesMs(1000, 0, [700, 726]),
        [1000000 - 726, 1000000],
      );
      expect(
        beatTimesMs(1000, 0, [650, 640, 660, 644]),
        [1000000 - 1944, 1000000 - 1304, 1000000 - 644, 1000000],
      );
    });

    test('the spacing IS the interval — the whole point of the column', () {
      final t = beatTimesMs(1000, 12345, [700, 726, 690]);
      expect(t[1]! - t[0]!, 726);
      expect(t[2]! - t[1]!, 690);
    });

    test('a broken interval nulls the beats BEFORE it, not after', () {
      // A non-positive interval means the gap before that beat is unknown, so
      // everything earlier in the record is unplaceable. Treating the missing
      // gap as zero would stack two beats on one instant and call it measured.
      expect(
        beatTimesMs(1000, 0, [700, 0, 690]),
        [null, 1000000 - 690, 1000000],
      );
    });

    test('an empty record produces nothing', () {
      expect(beatTimesMs(1000, 500, const []), isEmpty);
    });
  });

  group('the column is actually written', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    tearDown(() async => LocalDb.close());

    test('a record with a sub-second lands beat times; one without does not',
        () async {
      LocalDb.dbName = 'beat_ts_test.db';
      await LocalDb.close();
      final db = await LocalDb.instance;
      await db.delete('decoded_rr');
      await db.delete('decoded_onehz');

      final samples = [
        Sample(
          tsEpoch: 1700000000,
          counter: 1,
          hr: 74,
          rrIntervalsMs: const [700, 726],
          ax: 0.1,
          ay: 0.2,
          az: 0.9,
          spo2RedRaw: 1,
          spo2IrRaw: 1,
          skinTempRaw: 1,
          tsSubsec: 16384,
        ),
        // A record that carries no sub-second at all.
        Sample(
          tsEpoch: 1700000001,
          counter: 2,
          hr: 74,
          rrIntervalsMs: const [812],
          ax: 0.1,
          ay: 0.2,
          az: 0.9,
          spo2RedRaw: 1,
          spo2IrRaw: 1,
          skinTempRaw: 1,
        ),
      ];
      await LocalDb.insertRecordsBatch(
        [
          for (final s in samples)
            RawRecord(
              counter: s.counter,
              packetType: 47,
              hex: 'ff${s.counter}',
              capturedAt: s.tsEpoch * 1000,
              recTs: s.tsEpoch,
            ),
        ],
        samples,
      );

      final rows = await db.query('decoded_rr', orderBy: 'rec_ts, beat_index');
      expect(rows.map((r) => r['rr_ts_ms']), [
        1700000000 * 1000,
        1700000000 * 1000,
        1700000001 * 1000,
      ]);
      expect(rows.map((r) => r['beat_ts_ms']), [
        1700000000500 - 726,
        1700000000500,
        null,
      ]);
      // The measurement the model is built from is banked separately, so the
      // model is reversible.
      final onehz = await db.query('decoded_onehz', orderBy: 'rec_ts');
      expect(onehz.map((r) => r['ts_subsec']), [16384, null]);
    });
  });
}
