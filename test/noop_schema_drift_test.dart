// Regression tests for NOOP CSV schema drift (OpenStrap/edge#160).
//
// NOOP shipped a schema change that these tests pin:
//   • `band_sleep_state` INSERTED at index 15, shifting event_kind/event_payload
//     to 16/17 — the importer must keep reading by NAME, not position.
//   • new streams `steps` / `band_sleep_state` / `ppghr`.
//   • `spo2` and `resp` rows no longer emitted at all.
//
// Before this, `steps` fell into the importer's default branch: every imported
// day reported 0 steps while the band's own counter had measured thousands.
//
// There was no test that parsed a real NOOP CSV at all — only the pure
// `decideRow` ordering contract — which is why the drift shipped unnoticed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/import/noop_import.dart';

/// The CURRENT NOOP header — `band_sleep_state` at 15, event_* shifted to 16/17.
const _header = 'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z,'
    'step_counter,ppg_bpm,ppg_conf,spo2_red,spo2_ir,skintemp_raw,resp_raw,'
    'band_sleep_state,event_kind,event_payload';

/// Build one long-format row with only [stream]'s columns filled.
String _row(int ts, String stream,
    {String hr = '',
    String rr = '',
    String gx = '',
    String gy = '',
    String gz = '',
    String stepCounter = '',
    String skinTemp = '',
    String sleepState = '',
    String eventKind = '',
    String eventPayload = ''}) {
  final iso = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
      .toIso8601String();
  return [
    '$ts', iso, stream, hr, rr, gx, gy, gz, stepCounter, '', '', '', '',
    skinTemp, '', sleepState, eventKind, eventPayload,
  ].join(',');
}

void main() {
  group('stepRuns — cumulative counter → real step windows (pure)', () {
    test('sums positive deltas across one contiguous run', () {
      // 100 → 130 over 4 s = 30 steps, one window.
      final runs = NoopImporter.stepRuns({0: 100, 1: 110, 2: 120, 3: 130});
      expect(runs, [const StepRun(0, 3, 30)]);
    });

    test('splits on a gap wider than stepRunMaxGapSec', () {
      // The #160 export has a 20.5 h hole; a single window spanning it would
      // claim to cover — and therefore suppress the 1 Hz estimate over — a day
      // we have no samples for.
      final runs = NoopImporter.stepRuns({
        0: 100, 1: 110, // run A: +10
        5000: 500, 5001: 520, // run B: +20
      });
      expect(runs, [const StepRun(0, 1, 10), const StepRun(5000, 5001, 20)]);
    });

    test('a counter RESET is not a negative step count', () {
      // Band reboot: 900 → 0. Must not subtract 900, and must not fabricate.
      final runs = NoopImporter.stepRuns({0: 890, 1: 900, 2: 0, 3: 15});
      expect(runs, [const StepRun(0, 3, 25)]); // +10 then +15, reset ignored
    });

    test('does not attribute steps across a run boundary', () {
      // 100 → 900 happened DURING a 5000 s hole. We cannot say when, so the
      // delta is dropped rather than pinned to either window.
      final runs = NoopImporter.stepRuns({0: 100, 5000: 900, 5001: 905});
      expect(runs, [const StepRun(5000, 5001, 5)]);
    });

    test('emits nothing for a zero-step run', () {
      // A 0-step window would suppress a real 1 Hz estimate for no gain.
      expect(NoopImporter.stepRuns({0: 100, 1: 100, 2: 100}), isEmpty);
    });

    test('handles empty / single-sample input', () {
      expect(NoopImporter.stepRuns({}), isEmpty);
      expect(NoopImporter.stepRuns({5: 100}), isEmpty);
    });

    test('is order-independent', () {
      final a = NoopImporter.stepRuns({3: 130, 0: 100, 2: 120, 1: 110});
      expect(a, [const StepRun(0, 3, 30)]);
    });

    test('skips deltas already covered, and breaks the run there', () {
      // 0..5 covered → only the 5→8 tail is bankable.
      final runs = NoopImporter.stepRuns(
        {0: 100, 1: 110, 2: 120, 5: 150, 6: 160, 7: 170, 8: 180},
        covered: const [
          [0, 5]
        ],
      );
      expect(runs, [const StepRun(5, 8, 30)]);
    });

    test('a fully covered span banks nothing', () {
      expect(
        NoopImporter.stepRuns({0: 100, 1: 110, 2: 120},
            covered: const [
              [0, 2]
            ]),
        isEmpty,
      );
    });

    test('a covered span in the MIDDLE splits into two runs', () {
      final runs = NoopImporter.stepRuns(
        {0: 100, 1: 110, 2: 120, 3: 130, 4: 140, 5: 150},
        covered: const [
          [2, 3]
        ],
      );
      expect(runs, [const StepRun(0, 2, 20), const StepRun(3, 5, 20)]);
    });
  });

  group('end-to-end import of the CURRENT NOOP schema', () {
    late Directory tmp;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_noop_drift_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      tmp = await Directory.systemTemp.createTemp('noop_drift');
    });

    tearDownAll(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// ~40 min of 1 Hz data in the new schema, walking the step counter by 1/s.
    File writeCsv(String name, {required int t0, required int seconds}) {
      final b = StringBuffer()..writeln(_header);
      for (var i = 0; i < seconds; i++) {
        final ts = t0 + i;
        b.writeln(_row(ts, 'hr', hr: '${60 + (i % 20)}'));
        b.writeln(_row(ts, 'gravity', gx: '0.1', gy: '0.2', gz: '0.97'));
        b.writeln(_row(ts, 'skintemp', skinTemp: '3240'));
        b.writeln(_row(ts, 'steps', stepCounter: '${24302 + i}'));
        b.writeln(_row(ts, 'band_sleep_state', sleepState: '0'));
        if (i % 5 == 0) b.writeln(_row(ts, 'ppghr'));
      }
      // An event row whose QUOTED payload contains commas — the naive
      // `split(',')` must not let this corrupt unix_s / stream (indexes 0/2).
      b.writeln('${t0 + 1},x,event,,,,,,,,,,,,,,BATTERY_LEVEL(3),'
          '"{""battery_mV"":4155,""battery_pct"":78.4}"');
      final f = File(p.join(tmp.path, name))..writeAsStringSync(b.toString());
      return f;
    }

    test('banks the band step counter as REAL steps, and is idempotent',
        () async {
      // 2026-07-31T09:00:00Z, 2400 s of data.
      const t0 = 1785488400;
      const secs = 2400;
      final csv = writeCsv('a.csv', t0: t0, seconds: secs);

      final res = await NoopImporter.importFile(
          csv.path, const Profile(), DerivationEngine());

      // The whole point: steps are no longer silently dropped.
      expect(res.steps, secs - 1, reason: 'counter advanced 1/s for $secs s');
      expect(res.days, greaterThan(0));
      expect(res.lateRows, 0);

      // Banked where the derivation actually reads real steps from.
      final db = await LocalDb.instance;
      final cov = await db.query('live_coverage');
      expect(cov, isNotEmpty);
      final total = cov.fold<int>(0, (a, r) => a + (r['steps'] as int));
      expect(total, secs - 1);

      // RE-IMPORT must not double-count: live_coverage is an append-only SUM
      // with no uniqueness on the window.
      final res2 = await NoopImporter.importFile(
          csv.path, const Profile(), DerivationEngine());
      expect(res2.steps, 0, reason: 're-import banks nothing new');
      final cov2 = await db.query('live_coverage');
      expect(cov2.length, cov.length, reason: 'no duplicate windows');
      final total2 = cov2.fold<int>(0, (a, r) => a + (r['steps'] as int));
      expect(total2, total, reason: 'step total unchanged after re-import');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('an OVERLAPPING re-export does not double-count', () async {
      // The realistic re-import: the user exports again later over a LONGER
      // span covering the same session. An exact-window guard misses this
      // entirely (the run boundary moved), so the overlap gets banked twice —
      // measured at 3,598 against a true 2,399 before the covered-clipping fix.
      const t0 = 1785834000;
      final short = writeCsv('ov_short.csv', t0: t0, seconds: 1200);
      final long = writeCsv('ov_long.csv', t0: t0, seconds: 2400);

      final r1 = await NoopImporter.importFile(
          short.path, const Profile(), DerivationEngine());
      expect(r1.steps, 1199);

      final r2 = await NoopImporter.importFile(
          long.path, const Profile(), DerivationEngine());
      // Only the NEW tail is banked, not the whole longer span.
      expect(r2.steps, 2399 - 1199,
          reason: 'second import banks only the previously uncovered tail');

      final db = await LocalDb.instance;
      final cov = await db.query('live_coverage',
          where: 'start_ts >= ? AND start_ts < ?', whereArgs: [t0, t0 + 2400]);
      final total = cov.fold<int>(0, (a, r) => a + (r['steps'] as int));
      expect(total, 2399, reason: 'total equals the truth, not 3598');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('shifted event_kind/event_payload columns do not misparse', () async {
      // `band_sleep_state` at 15 pushes event_* to 16/17. Reading by NAME means
      // hr/gravity/steps still land correctly; a positional reader would not.
      const t0 = 1785574800; // a different day, so it derives independently
      final csv = writeCsv('b.csv', t0: t0, seconds: 600);
      final res = await NoopImporter.importFile(
          csv.path, const Profile(), DerivationEngine());
      expect(res.steps, 599);
      expect(res.rows, greaterThan(0));
      expect(res.lateRows, 0);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('an export with NO steps stream still imports (steps = 0)', () async {
      // `spo2`/`resp` already vanished from the schema; `steps` could too.
      const t0 = 1785661200;
      final b = StringBuffer()..writeln(_header);
      for (var i = 0; i < 600; i++) {
        b.writeln(_row(t0 + i, 'hr', hr: '65'));
        b.writeln(_row(t0 + i, 'gravity', gx: '0.1', gy: '0.2', gz: '0.97'));
      }
      final f = File(p.join(tmp.path, 'c.csv'))
        ..writeAsStringSync(b.toString());
      final res = await NoopImporter.importFile(
          f.path, const Profile(), DerivationEngine());
      expect(res.steps, 0);
      expect(res.days, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('an UNKNOWN future stream is skipped, not fatal', () async {
      const t0 = 1785747600;
      final b = StringBuffer()..writeln(_header);
      for (var i = 0; i < 300; i++) {
        b.writeln(_row(t0 + i, 'hr', hr: '65'));
        b.writeln(_row(t0 + i, 'gravity', gx: '0.1', gy: '0.2', gz: '0.97'));
        b.writeln(_row(t0 + i, 'some_future_stream_we_have_never_seen'));
      }
      final f = File(p.join(tmp.path, 'd.csv'))
        ..writeAsStringSync(b.toString());
      final res = await NoopImporter.importFile(
          f.path, const Profile(), DerivationEngine());
      expect(res.days, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
