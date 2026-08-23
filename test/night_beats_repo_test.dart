// getNightBeats — the one read path on LocalRepositoryImpl that goes back to
// the raw beat store, and the only new arithmetic the Beats screen needed.
//
// Two things it may not get wrong, and both are silent when they break:
//
//   * THE WINDOW. `decoded_rr` is keyed by `rec_ts` (seconds) while the sleep
//     window is `onset_ms`/`offset_ms` (milliseconds), so the bound conversion
//     is where beats get lost or borrowed a second at a time. Verified against
//     the owner's own `Export.db`: for the night of 2026-08-12 this window
//     yields 17 088 raw beats, which is exactly the `coverage.rr_beats` the
//     pipeline stored for that night — the same beats, not merely a similar
//     count. This test pins the boundary behaviour that produced it.
//
//   * PRUNED IS NOT BROKEN. Raw is deleted `rawRetentionDays` behind the data
//     edge while the derived bundle lives forever, so most nights in a real
//     install have a day_result and no beats at all. That must come back empty
//     and calm, never as an exception and never as a partial cloud.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A night that starts at [onsetSec] and runs [hours] long.
Future<void> _seedDay(Database db, String dayId, int onsetSec, num hours) =>
    db.insert('day_result', {
      'day_id': dayId,
      'algo_version': 61,
      'payload_json': '{}',
      'window_json': jsonEncode({
        'onset_ms': onsetSec * 1000,
        'offset_ms': (onsetSec + (hours * 3600).round()) * 1000,
      }),
      'computed_at': 1,
      'finalized': 1,
    });

/// One beat per second from [fromSec] to [toSec] inclusive.
Future<void> _seedBeats(Database db, int fromSec, int toSec) async {
  final batch = db.batch();
  for (var t = fromSec; t <= toSec; t++) {
    batch.insert('decoded_rr', {
      // v47: the key is (device_id, ts_ms, beat_index). A hand-written row that
      // omits ts_ms takes the DEFAULT 0 and collides with every other one.
      'ts_ms': t * 1000,
      'rec_ts': t,
      'beat_index': 0,
      'rr_ts_ms': t * 1000,
      // A steady 900 ms with a small physiologic wobble, so the corrector has
      // something ordinary to keep rather than a flat line to distrust.
      'rr_ms': 900 + (t % 7) * 4,
    });
  }
  await batch.commit(noResult: true);
}

void main() {
  late Database db;
  late String dir;
  final repo = LocalRepositoryImpl(getProfileMap: () => const {});

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_night_beats_test.db';
    dir = await databaseFactory.getDatabasesPath();
    await LocalDb.close();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    db = await LocalDb.instance;
  });

  tearDown(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('the window is the window — no beat either side of it', () async {
    const onset = 1786735958; // the real onset of 2026-08-15, to the second
    const hours = 2;
    const offset = onset + hours * 3600;
    // Beats for an hour either side of the night, so a sloppy bound shows up.
    await _seedDay(db, '2026-08-15', onset, hours);
    await _seedBeats(db, onset - 3600, offset + 3600);

    final got = await repo.getNightBeats('2026-08-15');

    // One beat per second, both ends inclusive.
    expect(got.rawBeats, offset - onset + 1);
    // Correction keeps what it keeps, but it cannot invent beats.
    expect(got.nn.length, lessThanOrEqualTo(got.rawBeats));
    expect(got.nn, isNotEmpty);
    expect(got.cleanFraction, greaterThan(.9));
  });

  test('a night whose beats were pruned comes back empty, not broken',
      () async {
    // The steady state: the derived row survives, the raw behind it does not.
    await _seedDay(db, '2026-08-01', 1786000000, 8);
    final got = await repo.getNightBeats('2026-08-01');
    expect(got.nn, isEmpty);
    expect(got.rawBeats, 0);
  });

  test('a day with no derived row asks the beat store nothing', () async {
    final got = await repo.getNightBeats('1999-01-01');
    expect(got.nn, isEmpty);
    expect(got.rawBeats, 0);
  });

  test('a day whose window never resolved is absent, not the whole store',
      () async {
    // `window_json` is `'{}'` for a day the sleep detector produced no window.
    // Falling back to "everything" here would draw a scatter of the entire
    // record under a single night's date.
    await db.insert('day_result', {
      'day_id': '2026-08-02',
      'algo_version': 61,
      'payload_json': '{}',
      'window_json': '{}',
      'computed_at': 1,
      'finalized': 1,
    });
    await _seedBeats(db, 1786000000, 1786003600);
    final got = await repo.getNightBeats('2026-08-02');
    expect(got.nn, isEmpty);
    expect(got.rawBeats, 0);
  });
}
