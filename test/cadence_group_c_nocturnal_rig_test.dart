// GROUP C1 ON REAL DATA — what `nocturnalRhr` does at a slower cadence once it
// is given the clock.
//
// `cadence_decimation_rig_test.dart` measures the DEFECT: its probe feeds the
// bare HR list, which is exactly how the app feeds it today, so the cell it
// reports is the positional-window error (59.7 → 66.4 bpm at 15 s). That probe
// must keep doing that — it is the baseline everything else diffs against — so
// the fix is measured here instead, on the same night of the same export, with
// `tsSec` supplied.
//
// Run:
//   OPENSTRAP_TEST_DBS=~/Documents/openstrap/openstrap_export_1786730410696.db \
//     flutter test test/cadence_group_c_nocturnal_rig_test.dart --concurrency=1
//
// Skips cleanly with no export, and reads the night window the rig already
// picked out of `build/cadence_baseline.json` rather than re-deriving it —
// same window, no second copy of the picker.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/compute/substrate.dart' show plausibleHrOrNull;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _cadences = <int>[1, 5, 15, 60, 300, 301];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final src = (Platform.environment['OPENSTRAP_TEST_DBS'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (src.isEmpty) {
    test('C1 real-data measurement', () {}, skip: 'set OPENSTRAP_TEST_DBS');
  }

  for (final path in src) {
    test('C1 nocturnalRhr with a clock, over ${p.basename(path)}', () async {
      final baseline =
          File(p.join(Directory.current.path, 'build', 'cadence_baseline.json'));
      if (!baseline.existsSync()) {
        markTestSkipped('run cadence_decimation_rig_test.dart first');
        return;
      }
      final meta = jsonDecode(await baseline.readAsString()) as Map;
      final win = (meta['night_window'] as List).cast<int>();

      final db = await databaseFactory
          .openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
      final rows = await db.query('decoded_onehz',
          columns: ['rec_ts', 'hr'],
          where: 'rec_ts >= ? AND rec_ts < ?',
          whereArgs: [win[0], win[1]],
          orderBy: 'rec_ts');
      await db.close();

      final ts = [for (final r in rows) (r['rec_ts'] as int).toDouble()];
      final hr = [for (final r in rows) (r['hr'] as int).toDouble()];
      expect(hr.length, greaterThan(1000));

      double? truth;
      for (final n in _cadences) {
        final dts = <double>[], dhr = <double>[];
        for (var i = 0; i < ts.length; i++) {
          if ((ts[i] - ts.first) % n == 0) {
            dts.add(ts[i]);
            dhr.add(hr[i]);
          }
        }
        final blind = nocturnalRhr(dhr); // what the app does today
        final timed = nocturnalRhr(dhr, tsSec: dts); // what C1 adds
        truth ??= timed.value?.low30Mean;
        String f(double? v) => v == null ? 'ABSENT' : v.toStringAsFixed(2);
        String err(double? v) => (v == null || truth == null)
            ? '—'
            : '${((v - truth) / truth * 100).toStringAsFixed(1)}%';
        // ignore: avoid_print
        print('[C1] ${n.toString().padLeft(3)}s  '
            'no-ts ${f(blind.value?.low30Mean).padLeft(6)} ${err(blind.value?.low30Mean).padLeft(7)}   '
            'ts ${f(timed.value?.low30Mean).padLeft(6)} ${err(timed.value?.low30Mean).padLeft(7)}   '
            'conf ${timed.confidence.toStringAsFixed(2)}');

        if (n == 1) {
          // THE GATE: 1 Hz is bit-identical with and without the clock, and
          // identical to the rig's recorded truth.
          expect(timed.value!.low30Mean, blind.value!.low30Mean);
          expect(timed.confidence, blind.confidence);
          final cell = (meta['cells'] as List).firstWhere((c) =>
              c['metric'] == 'nocturnalRhr' && c['cadence_s'] == 1) as Map;
          expect(timed.value!.low30Mean, cell['value']);
        } else if (n <= 300) {
          // Every cadence a real band ships lands on the 1 Hz trough, or says
          // nothing. A number within 2% is the bar; 15 s was +11.2% before.
          expect(timed.present, isTrue, reason: '${n}s: ${timed.note}');
          expect((timed.value!.low30Mean - truth!) / truth, closeTo(0, 0.02),
              reason: '${n}s');
        } else {
          // Past what `sampleCadenceSeconds` will vouch for: absent, always.
          expect(timed.present, isFalse, reason: '${n}s: ${timed.value}');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    // WHAT THE WIRING ACTUALLY MOVES. The test above decimates one night to
    // show the defect at other cadences; this one asks the only question that
    // decides whether shipping `tsSec` changes a published number TODAY, at
    // 1 Hz, on this owner's own nights: for every real sleep window the app
    // scored, is `nocturnalRhr(hr)` the same value as `nocturnalRhr(hr, tsSec)`?
    //
    // The windows come from `day_result.window_json` (the segmentation the app
    // already ran — C1 does not move it) and the HR is read exactly as
    // `derive_prepare` builds `Substrate.hr`, so the pair of numbers printed
    // here is the pair the pipeline would publish. Days whose decoded rows have
    // been pruned past the retention edge have no substrate to re-score and are
    // skipped, which on a 3-day-retention export is most of them.
    test('C1 wired: real sleep windows, blind vs timed, over '
        '${p.basename(path)}', () async {
      final db = await databaseFactory
          .openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
      final days = await db.query('day_result',
          columns: ['day_id', 'algo_version', 'rhr', 'window_json'],
          orderBy: 'day_id, algo_version');
      var scored = 0;
      for (final d in days) {
        final w = jsonDecode((d['window_json'] as String?) ?? '{}');
        if (w is! Map || w['onset_ms'] == null || w['offset_ms'] == null) {
          continue;
        }
        final on = ((w['onset_ms'] as num) / 1000).round();
        final off = ((w['offset_ms'] as num) / 1000).round();
        final rows = await db.query('decoded_onehz',
            columns: ['rec_ts', 'hr'],
            where: 'rec_ts >= ? AND rec_ts < ?',
            whereArgs: [on, off],
            orderBy: 'rec_ts');
        if (rows.isEmpty) continue;
        scored++;
        final ts = [for (final r in rows) (r['rec_ts'] as int).toDouble()];
        final hr = [
          for (final r in rows)
            (plausibleHrOrNull((r['hr'] as num?)?.toInt() ?? 0) ?? 0).toDouble(),
        ];
        final blind = nocturnalRhr(hr);
        final timed = nocturnalRhr(hr, tsSec: ts);
        String f(double? v) => v == null ? 'ABSENT' : v.toStringAsFixed(3);
        final b = blind.value?.low30Mean, t = timed.value?.low30Mean;
        final delta = (b == null || t == null) ? '—' : (t - b).toStringAsFixed(3);
        // ignore: avoid_print
        print('[C1-wired] ${d['day_id']} v${d['algo_version']}  '
            'span ${off - on}s rows ${rows.length} (holes ${off - on - rows.length})  '
            'stored ${f((d['rhr'] as num?)?.toDouble())}  '
            'blind ${f(b)}  timed ${f(t)}  Δ $delta');
      }
      await db.close();
      // Not an assertion about the values — this rig exists to REPORT them. The
      // only thing it guards is that it actually measured something.
      expect(scored, greaterThan(0),
          reason: 'no scored sleep window still has decoded rows');
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
