// Local persistence round-trips for the v7 user-data tables (journal / cycle /
// sessions / notifications). Runs the REAL LocalDb against an in-memory sqlite
// via sqflite_common_ffi — no platform plugins needed.
//
// Covers: journal upsert+read (idempotent on date), a workout session
// round-trip (live → done finalize), and notification idempotency (INSERT OR
// IGNORE keeps the generator from duplicating across passes).

import '../support/typed_decoded_fixture.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import '../support/store_fixtures.dart';

void main() {
  // Route sqflite through the FFI factory so LocalDb.instance opens a real
  // schema (onCreate builds the v7 tables). Delete any leftover file from a
  // prior run so each suite starts clean (LocalDb owns the whoop.db path).
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'whoop_persistence_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('journal upsert + read (idempotent on date)', () async {
    const date = '2026-06-20';
    await JournalStore.put(
      date,
      jsonEncode(['caffeine', 'late meal']),
      'felt wired',
    );
    var rows = await JournalStore.entries();
    final row = rows.firstWhere((r) => r['date'] == date);
    expect(jsonDecode(row['tags_json'] as String), ['caffeine', 'late meal']);
    expect(row['note'], 'felt wired');

    // Re-put the same date → REPLACE, not a duplicate row.
    await JournalStore.put(date, jsonEncode(['rest day']), 'recovered');
    rows = await JournalStore.entries();
    final same = rows.where((r) => r['date'] == date).toList();
    expect(same.length, 1);
    expect(jsonDecode(same.first['tags_json'] as String), ['rest day']);
    expect(same.first['note'], 'recovered');

    // sinceDaysEpoch lower bound excludes older rows.
    await JournalStore.put('2020-01-01', '[]', 'ancient');
    final recent = await JournalStore.entries(sinceDaysEpoch: '2026-01-01');
    expect(recent.any((r) => r['date'] == '2020-01-01'), isFalse);
    expect(recent.any((r) => r['date'] == date), isTrue);
  });

  test('workout session round-trip (live → finalized done)', () async {
    const id = 'w1700000000000';
    final startSec = 1700000000;
    await LocalDb.putSession({
      'id': id,
      'start_ts': startSec,
      'end_ts': null,
      'type': 'run',
      'status': 'live',
      'source': 'manual',
      'created_at': startSec * 1000,
    });
    var s = await LocalDb.session(id);
    expect(s, isNotNull);
    expect(s!['status'], 'live');

    // Finalize: same id, REPLACE with stats.
    await LocalDb.putSession({
      'id': id,
      'start_ts': startSec,
      'end_ts': startSec + 1800,
      'type': 'run',
      'status': 'done',
      'calories': 220.0,
      'strain': 9.4,
      'max_hr': 171,
      'duration_min': 30,
      'zone_min_json': jsonEncode(const <num>[]),
      'source': 'manual',
      'created_at': startSec * 1000,
    });
    s = await LocalDb.session(id);
    expect(s!['status'], 'done');
    expect(s['calories'], 220.0);
    expect(s['max_hr'], 171);
    expect(s['duration_min'], 30);

    // In-range query finds it; type setter mutates it; delete removes it.
    final inRange = await LocalDb.sessionsInRange(startSec - 10, startSec + 10);
    expect(inRange.any((r) => r['id'] == id), isTrue);
    await LocalDb.setSessionType(id, 'cycling');
    expect((await LocalDb.session(id))!['type'], 'cycling');
    await LocalDb.deleteSession(id);
    expect(await LocalDb.session(id), isNull);
  });

  test('cycle logs read oldest first', () async {
    await seedCycleLog('2026-05-29', 'start');
    await seedCycleLog('2026-05-01', 'start');
    final logs = await LocalDb.cycleLogs();
    final dates = logs.map((r) => r['date']).toList();
    expect(dates.indexOf('2026-05-01') < dates.indexOf('2026-05-29'), isTrue);
  });

  test(
    'decoded substrate tables persist and query 1 Hz frames + RR beats',
    () async {
      final startSec =
          DateTime(2026, 6, 27, 10, 0).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.insertRecord(
        RawRecord(
          counter: 424242,
          packetType: 47,
          hex: 'ignored-by-decoded-test',
          capturedAt: startSec * 1000,
          recTs: startSec,
        ),
        Sample(
          tsEpoch: startSec,
          counter: 424242,
          hr: 61,
          rrIntervalsMs: const [980, 1005],
          ax: 0.1,
          ay: -0.2,
          az: 0.97,
          spo2RedRaw: 1234,
          spo2IrRaw: 2345,
          skinTempRaw: 3456,
        ),
      );

      final frames = await LocalDb.decodedOneHzBatchByRecTsRange(
        limit: 10,
        fromRecTs: startSec - 1,
        toRecTs: startSec + 1,
      );
      expect(frames, hasLength(1));
      expect(frames.first['counter'], 424242);
      expect(frames.first['hr'], 61);
      expect(frames.first['spo2_red_raw'], 1234);

      final rr = await LocalDb.decodedRrByRecTsRange(
        fromRecTs: startSec,
        toRecTs: startSec,
      );
      expect(rr, hasLength(2));
      expect(rr.first['rr_ms'], 980);
      expect(rr.last['rr_ms'], 1005);

      final ranged = await readTypedDecodedFixture(startSec - 1, startSec + 1);
      expect(ranged, hasLength(1));
      expect(ranged.first.counter, 424242);

      final stats = await LocalDb.rawStats();
      expect(stats['decoded_onehz'], greaterThanOrEqualTo(1));
      expect(stats['decoded_rr'], greaterThanOrEqualTo(2));
    },
  );

  test(
    'counter reset does not quarantine the decoded second (newest-wins by rec_ts)',
    () async {
      // Reproduce the reboot bug: the strap counter RESETS to ~0 on reboot, so a
      // post-reboot record can land on a second that a pre-reboot (high-counter)
      // record already wrote. The decoded store dedupes by rec_ts; the OLD
      // INSERT-OR-IGNORE dropped the newcomer → everything after a reboot became
      // invisible to analytics. It must now REPLACE (newest-wins) so the fresh
      // record is kept.
      final sec = DateTime(2026, 6, 30, 2, 0).millisecondsSinceEpoch ~/ 1000;

      // Pre-reboot record: high counter, this second.
      await LocalDb.insertRecord(
        RawRecord(
          counter: 34000000,
          packetType: 47,
          hex: 'pre-reboot',
          capturedAt: sec * 1000,
          recTs: sec,
        ),
        Sample(
          tsEpoch: sec,
          counter: 34000000,
          hr: 61,
          ax: 0.0,
          ay: 0.0,
          az: 1.0,
          spo2RedRaw: 1,
          spo2IrRaw: 1,
          skinTempRaw: 1,
        ),
      );

      // Post-reboot record: counter has reset to a low value, SAME second, but a
      // fresher reading (hr=77). Under the old IGNORE this was dropped.
      await LocalDb.insertRecord(
        RawRecord(
          counter: 42,
          packetType: 47,
          hex: 'post-reboot',
          capturedAt: (sec + 3600) * 1000,
          recTs: sec,
        ),
        Sample(
          tsEpoch: sec,
          counter: 42,
          hr: 77,
          ax: 0.0,
          ay: 0.0,
          az: 1.0,
          spo2RedRaw: 2,
          spo2IrRaw: 2,
          skinTempRaw: 2,
        ),
      );

      final frames = await LocalDb.decodedOneHzBatchByRecTsRange(
        limit: 10,
        fromRecTs: sec - 1,
        toRecTs: sec + 1,
      );
      // Exactly one row for the second, and it is the POST-reboot reading.
      expect(frames, hasLength(1));
      expect(frames.first['hr'], 77);
      expect(frames.first['counter'], 42);

      // A post-reboot record on a brand-new second is also stored (not gated by
      // any stale counter high-water).
      await LocalDb.insertRecord(
        RawRecord(
          counter: 43,
          packetType: 47,
          hex: 'post-reboot-2',
          capturedAt: (sec + 3601) * 1000,
          recTs: sec + 1,
        ),
        Sample(
          tsEpoch: sec + 1,
          counter: 43,
          hr: 78,
          ax: 0.0,
          ay: 0.0,
          az: 1.0,
          spo2RedRaw: 3,
          spo2IrRaw: 3,
          skinTempRaw: 3,
        ),
      );
      final after = await LocalDb.decodedOneHzBatchByRecTsRange(
        limit: 10,
        fromRecTs: sec - 1,
        toRecTs: sec + 2,
      );
      expect(after, hasLength(2));
    },
  );

  test(
    'structured band signals persist event history and battery samples',
    () async {
      const eventHex = '3000070000105e5f';
      await LocalDb.insertEvent(7, 1600000000, eventHex);
      await LocalDb.insertBandBatterySample(
        ts: 1600000100,
        batteryPct: 77.0,
        charging: true,
        wristOn: true,
        source: 'device_state',
      );

      final db = await LocalDb.instance;
      final events = await db.query('band_events');
      final battery = await db.query('band_battery', orderBy: 'ts DESC');
      expect(events, isNotEmpty);
      expect(battery, isNotEmpty);
      expect(battery.first['battery_pct'], 77.0);
      expect(battery.first['charging'], 1);
      expect(events.where((r) => r['name'] == 'CHARGING_ON'), isNotEmpty);
    },
  );
  // ── resumable-sync cursor ──────────────────────────────────────────────────────
  // Kept in THIS file (not a separate suite) so it shares the single DB-test
  // isolate — two test files both opening LocalDb's fixed whoop.db path race
  // on the on-disk sqlite file.
  test('sync cursor set/get round-trip + int parse', () async {
    expect(await LocalDb.getCursor('strap_trim'), isNull);
    await LocalDb.setCursor('strap_trim', 'deadbeef0102');
    expect(await LocalDb.getCursor('strap_trim'), 'deadbeef0102');
    await LocalDb.setCursor('strap_trim', 'cafe'); // REPLACE, not duplicate
    expect(await LocalDb.getCursor('strap_trim'), 'cafe');
    await LocalDb.setCursor('rec_ts_hw', '1750000000');
    expect(await LocalDb.getCursorInt('rec_ts_hw'), 1750000000);
    expect(await LocalDb.getCursorInt('missing'), isNull);
  });

  test(
    'commitSyncBatch persists decoded rows + advances high-water + stores trim token',
    () async {
      RawRecord raw(int counter, int recTs) => RawRecord(
        counter: counter,
        packetType: 47,
        hex: 'aa$counter',
        capturedAt: 1750000000000,
        recTs: recTs,
      );
      await LocalDb.commitSyncBatch(
        [raw(10, 1750000100), raw(11, 1750000200)],
        [
          Sample(tsEpoch: 1750000100, counter: 10, hr: 60),
          Sample(tsEpoch: 1750000200, counter: 11, hr: 61),
        ],
        trimToken: 'aa00bb11cc22dd33',
      );
      final counts = await LocalDb.counts();
      expect(counts['raw'], greaterThanOrEqualTo(2));
      expect(await LocalDb.getCursorInt('counter_hw'), 11);
      expect(await LocalDb.getCursorInt('rec_ts_hw'), 1750000200);
      expect(await LocalDb.getCursor('strap_trim'), 'aa00bb11cc22dd33');
    },
  );

  test(
    'high-water only advances (a re-delivered older batch never regresses it)',
    () async {
      await LocalDb.commitSyncBatch(
        [
          RawRecord(
            counter: 5,
            packetType: 47,
            hex: 'aa5',
            capturedAt: 1750000000000,
            recTs: 1750000050,
          ),
        ],
        [Sample(tsEpoch: 1750000050, counter: 5, hr: 59)],
        trimToken: 'beef',
      );
      expect(await LocalDb.getCursorInt('counter_hw'), 11); // unchanged
      expect(await LocalDb.getCursorInt('rec_ts_hw'), 1750000200); // unchanged
      expect(
        await LocalDb.getCursor('strap_trim'),
        'beef',
      ); // always latest ACK
    },
  );
}
