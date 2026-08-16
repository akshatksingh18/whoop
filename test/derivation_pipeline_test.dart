// Integration test for the on-device V2 compute path:
//   real raw frames (whoop_hist.jsonl) → decodeSubstrate (ONE decode point)
//   → physiologicalDays (wake-to-wake segmentation) → DayBundleInput
//   → deriveDayBundle (the pure isolate entry, called SYNCHRONOUSLY)
//   → assert a sane derived bundle (RHR, an HRV value, no crash).
//
// Also shapes the bundle the way LocalRepositoryImpl.getToday() does and asserts
// it is a well-formed Today map.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  File? fixtureFile() {
    final candidates = [
      '../whoop_hist.jsonl',
      '../../whoop_hist.jsonl',
      'whoop_hist.jsonl',
    ];
    for (final c in candidates) {
      final file = File(c);
      if (file.existsSync()) return file;
    }
    return null;
  }

  // The backfill/insert fix: rec_ts must come from the frame's REAL device time,
  // never from receive time. decodeRecTs is the pure resolver used at insert AND
  // in the v6 migration backfill — if it returned the fallback (≈now) the whole
  // multi-day backfill would collapse into one "today" bucket and hang derivation.
  // The fixture is a real band capture kept beside the repo, not inside it, so
  // it is there for local runs and absent in CI. Skip rather than fail when it
  // is missing — a green CI must not depend on an untracked file.
  final skipNoFixture = fixtureFile() == null
      ? 'whoop_hist.jsonl fixture not found beside the repo'
      : null;

  test('decodeRecTs reads the frame\'s real ts, not the fallback', () {
    final f = fixtureFile();
    expect(f, isNotNull, reason: 'whoop_hist.jsonl fixture not found');

    const sentinelFallback = 111; // a value the real ts can never equal
    final dayLabels = <String>{};
    var decodedCount = 0;
    for (final line in f!.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final hex = (jsonDecode(line) as Map<String, dynamic>)['hex'] as String?;
      if (hex == null) continue;
      final ts = LocalDb.decodeRecTs(hex, fallbackSec: sentinelFallback);
      if (ts == sentinelFallback) continue; // undecodable frame (events etc.)
      decodedCount++;
      expect(
        ts,
        greaterThan(1600000000),
        reason: 'a real 2020+ epoch, not fallback',
      );
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: false);
      dayLabels.add('${d.year}-${d.month}-${d.day}');
    }
    expect(decodedCount, greaterThan(50), reason: 'decoded real frames');
    // Every decoded frame bucketed by its own real day (here all one day).
    expect(dayLabels, isNotEmpty);
  }, skip: skipNoFixture);

  test('V2 path: decodeSubstrate → segmentation → deriveDayBundle is sane', () {
    final f = fixtureFile();
    expect(f, isNotNull, reason: 'whoop_hist.jsonl fixture not found');

    final hexes = <String>[];
    for (final line in f!.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final m = jsonDecode(line) as Map<String, dynamic>;
      final hex = m['hex'] as String?;
      if (hex != null) hexes.add(hex);
    }
    expect(hexes.length, greaterThan(100), reason: 'expected real frames');

    // ── ONE decode point: raw hex → Substrate ────────────────────────────────
    final sub = decodeSubstrate(hexes);
    expect(sub.length, greaterThan(50), reason: 'decoded 1 Hz substrate');
    expect(
      sub.hr.where((h) => h > 0).length,
      greaterThan(50),
      reason: 'valid HR samples',
    );
    expect(sub.rrMs.length, greaterThan(50), reason: 'decoded RR beats');

    // ── calendar-day segmentation: a day always exists when there's data ──────
    // The fixture is ~9 min — too short to qualify as a ≥3 h main sleep, so the
    // day is emitted with no sleep (flag NO_SLEEP_DETECTED).
    final days = calendarDays(sub);
    expect(days, isNotEmpty, reason: 'a calendar day always exists');
    final day = days.first;

    // ── coordinator slice → DayBundleInput → deriveDayBundle (synchronous) ────
    // The fixture is ~9 min. Nocturnal RHR needs ≥~15 min (half its 30-min
    // window) of valid HR. Tile the REAL decoded HR/RR forward in time to ~30 min
    // so the night-grade clinical metrics exercise on genuine values — no
    // synthetic numbers, just real samples repeated along a continuous timeline.
    // Treat the whole tiled capture as both the day span AND the HRV/RHR window
    // (in lieu of a qualifying sleep), mirroring the engine's slicing without a DB.
    final n0 = sub.length;
    final tiles = (1800 / n0).ceil() + 1;
    final dayTs = <int>[], dayHr = <int>[];
    final sRed = <int>[], sIr = <int>[], sTemp = <int>[];
    final rrTs = <double>[], rrMs = <double>[];
    final base = sub.tsSec.first;
    for (var t = 0; t < tiles; t++) {
      final shift = t * (n0 + 1);
      for (var i = 0; i < n0; i++) {
        dayTs.add(base + shift + i);
        dayHr.add(sub.hr[i]);
        sRed.add(sub.spo2Red[i]);
        sIr.add(sub.spo2Ir[i]);
        sTemp.add(sub.skinTemp[i]);
      }
      // Re-anchor each RR beat into this tile's second (preserves order/spacing).
      for (var i = 0; i < sub.rrMs.length; i++) {
        rrTs.add(sub.rrTsMs[i] + shift * 1000.0);
        rrMs.add(sub.rrMs[i]);
      }
    }
    final hypno = <String>[
      for (final s in day.sleep.stages)
        s == ana.SleepStage.wake
            ? 'wake'
            : (s == ana.SleepStage.rem ? 'rem' : 'nrem'),
    ];
    final input = DayBundleInput(
      date: day.date,
      dayTsSec: dayTs,
      dayHr: dayHr,
      sleepTsSec: dayTs,
      sleepHr: dayHr,
      sleepRrTsMs: rrTs,
      sleepRrMs: rrMs,
      sleepSpo2Red: sRed,
      sleepSpo2Ir: sIr,
      sleepSkinTemp: sTemp,
      sleepJson: day.sleep.toJson(),
      hypnoStages: hypno,
      sleepOnsetSec: dayTs.first,
      sleepOffsetSec: dayTs.last + 1,
      profile: const {'age': 30, 'sex': 'm', 'weight': 75, 'height': 178},
      dayConfidence: day.confidence,
      dayFlags: day.flags,
    ).toJson();

    final bundle = deriveDayBundle(input);

    // Bundle is well-formed + JSON-serializable.
    expect(bundle['date'], day.date);
    expect(() => jsonEncode(bundle), returnsNormally);

    final scalars = (bundle['scalars'] as Map).cast<String, dynamic>();
    // RHR present + physiologically plausible.
    expect(scalars['rhr'], isNotNull, reason: 'nocturnal RHR computed');
    expect(scalars['rhr'] as num, inInclusiveRange(25, 220));
    // An HRV value present + positive.
    expect(scalars['rmssd'], isNotNull, reason: 'RMSSD computed');
    expect(scalars['rmssd'] as num, greaterThan(0));

    // Clinical envelopes carry the honest {value,confidence,tier} shape.
    final clinical = (bundle['clinical'] as Map).cast<String, dynamic>();
    final hrvTime = (clinical['hrv_time'] as Map).cast<String, dynamic>();
    expect(hrvTime['tier'], anyOf('HIGH', 'AUTH'));
    expect(hrvTime['confidence'] as num, greaterThan(0));

    // Coverage diagnostics.
    final cov = (bundle['coverage'] as Map).cast<String, dynamic>();
    expect(cov['nn_clean'] as num, greaterThan(0));

    // The NOCTURNAL-only resting HR is published beside the general one. This
    // fixture has no detected sleep, so it is ABSENT while `rhr` (which may
    // fall back to daytime HR for the resting-HR card) is present — exactly the
    // pair the strain path needs to be able to tell apart.
    expect(scalars.containsKey('rhr_nocturnal'), isTrue);
    expect(scalars['rhr_nocturnal'], isNull,
        reason: 'no sleep session → no nocturnal RHR, whatever `rhr` says');

    // hrv_timeline.t is EPOCH SECONDS, on the same axis as hr_curve — the
    // v_series contract and the coach prompt both promise that, and the stored
    // `t` used to be seconds since the first NN beat (single digits).
    final series = (bundle['series'] as Map).cast<String, dynamic>();
    final tl = (series['hrv_timeline'] as List).cast<Map>();
    expect(tl, isNotEmpty, reason: '~30 min of NN should yield 5-min windows');
    final firstT = (tl.first['t'] as num).toInt();
    expect(firstT, greaterThan(1600000000), reason: 'epoch seconds, not 1970');
    expect(firstT, greaterThanOrEqualTo(dayTs.first),
        reason: 'inside the day it belongs to');
    expect(firstT, lessThanOrEqualTo(dayTs.last + 60));
    // A FULL 5-minute window before the first point. It used to emit after 10
    // beats (~8 s) onto a line documented as rolling 5-min windows.
    expect(firstT - dayTs.first, greaterThanOrEqualTo(300));

    // (The secondary Edwards "effort" strain block was removed in the PR#25
    // pipeline refactor; the headline 0–21 strain remains via scalars['strain'].)

    // Winsorized-EWMA personal baselines for rhr/hrv/resp, each carrying the
    // BaselineState fields + a cold-start status (calibrating on a single night).
    final baselines = (bundle['baselines'] as Map).cast<String, dynamic>();
    for (final k in const ['resting_hr', 'hrv', 'resp']) {
      final b = (baselines[k] as Map).cast<String, dynamic>();
      expect(b.containsKey('baseline'), isTrue, reason: '$k baseline');
      expect(b.containsKey('spread'), isTrue, reason: '$k spread');
      expect(
          b['status'],
          anyOf('calibrating', 'provisional', 'trusted', 'stale'),
          reason: '$k status');
    }
    // Whole bundle still JSON-serializable with the new blocks.
    expect(() => jsonEncode(bundle['baselines']), returnsNormally);

    // ── shape it like getToday() and assert a well-formed Today map ──────────
    final today = _shapeToday(bundle);
    expect(today['daily'], isA<Map>());
    final daily = (today['daily'] as Map).cast<String, dynamic>();
    final rhrMetric = (daily['resting_hr'] as Map).cast<String, dynamic>();
    expect(rhrMetric['value'], isNotNull);
    expect(rhrMetric['value'], isNot('—'));
  }, skip: skipNoFixture);

  // ── synthetic, fixture-free: the seams the day bundle publishes ────────────
  group('the day bundle seams', () {
    const t0 = 1786700000;

    Map<String, dynamic> bundleFor({
      required List<String> stages,
      String sleepSource = 'auto',
      int tempEvery = 1,
      String? deviceFamily = 'gen4',
    }) {
      final n = stages.length;
      final ts = <int>[for (var i = 0; i < n; i++) t0 + i];
      final hr = <int>[for (var i = 0; i < n; i++) 55];
      return deriveDayBundle(DayBundleInput(
        date: '2026-08-15',
        dayTsSec: ts,
        dayHr: hr,
        sleepTsSec: ts,
        sleepHr: hr,
        sleepRrTsMs: const [],
        sleepRrMs: const [],
        sleepSpo2Red: List<int>.filled(n, 0),
        sleepSpo2Ir: List<int>.filled(n, 0),
        // One temp sample every `tempEvery` seconds; 0 is the absent sentinel.
        sleepSkinTemp: <int>[
          for (var i = 0; i < n; i++) i % tempEvery == 0 ? 3000 : 0,
        ],
        sleepJson: {
          'tst_sec': n,
          'in_bed_sec': n,
          'unobserved_sec': stages.where((s) => s == 'unobserved').length,
          'window': {'onset_ms': t0 * 1000, 'offset_ms': (t0 + n) * 1000},
        },
        hypnoStages: stages,
        sleepOnsetSec: t0,
        sleepOffsetSec: t0 + n,
        profile: const {
          'age': 35,
          'sex': 'm',
          'weight_kg': 75,
          'height_cm': 178,
        },
        deviceFamily: deviceFamily,
        sleepSource: sleepSource,
      ).toJson());
    }

    Map<String, dynamic> accountingOf(Map<String, dynamic> b) =>
        (((b['sleep'] as Map)['accounting'] as Map)['value'] as Map)
            .cast<String, dynamic>();

    // Two hours of sleep, a one-hour hole, two more hours. A naive longest-run
    // bridges the hole and prints five hours of unbroken sleep.
    test('the longest unbroken stretch never bridges an unobserved hole', () {
      final acc = accountingOf(bundleFor(stages: <String>[
        ...List<String>.filled(7200, 'light'),
        ...List<String>.filled(3600, 'unobserved'),
        ...List<String>.filled(7200, 'light'),
      ]));
      expect(acc['longest_sleep_sec'], 7200);
      expect(acc['unobserved_sec'], 3600);
      expect(acc['observed_in_bed_sec'], 14400);
      // And the hole is not an awakening — we did not see anyone wake up.
      expect(acc['awakenings'], 0);
    });

    test('only sustained wake runs count as awakenings', () {
      final acc = accountingOf(bundleFor(stages: <String>[
        ...List<String>.filled(3600, 'light'),
        ...List<String>.filled(600, 'wake'),
        ...List<String>.filled(3600, 'rem'),
        ...List<String>.filled(60, 'wake'),
        ...List<String>.filled(3600, 'light'),
      ]));
      expect(acc['awakenings'], 1);
    });

    // On the auto path the window cannot begin before you are already still
    // with a sleep-ish heart rate, so a latency measured off it is not the
    // number people read it as.
    test('sleep-onset latency is published only on a forced window', () {
      final stages = <String>[
        ...List<String>.filled(900, 'wake'),
        ...List<String>.filled(3600, 'light'),
      ];
      expect(accountingOf(bundleFor(stages: stages))['sol_sec'], isNull);
      expect(
        accountingOf(
            bundleFor(stages: stages, sleepSource: 'manual'))['sol_sec'],
        900,
      );
      // …and never when the leading edge went unwatched.
      expect(
        accountingOf(bundleFor(
          stages: <String>[
            'unobserved',
            ...List<String>.filled(899, 'wake'),
            ...List<String>.filled(3600, 'light'),
          ],
          sleepSource: 'manual',
        ))['sol_sec'],
        isNull,
      );
    });

    // How much of "last night" a nightly skin temperature is actually made of.
    test('the temperature mean carries its coverage fraction', () {
      final scalars =
          (bundleFor(stages: List<String>.filled(7200, 'light'), tempEvery: 10)[
                  'scalars'] as Map)
              .cast<String, dynamic>();
      expect(scalars['skin_temp_adc'], isNotNull);
      expect(scalars['skin_temp_coverage_frac'] as num, closeTo(0.1, 0.001));
    });

    // One ceiling, dispatched on the strap — and no ceiling at all when we
    // cannot say which strap measured the heart rate.
    test('an unstamped strap gets no HR ceiling, so nothing is banded on one',
        () {
      final stamped =
          (bundleFor(stages: List<String>.filled(3600, 'light'))['scalars']
                  as Map)
              .cast<String, dynamic>();
      expect(stamped['max_hr_used'] as num, closeTo(208 - 0.7 * 35, 0.001));
      final unstamped = (bundleFor(
        stages: List<String>.filled(3600, 'light'),
        deviceFamily: null,
      )['scalars'] as Map)
          .cast<String, dynamic>();
      expect(unstamped['max_hr_used'], isNull);
      expect(unstamped['trimp'], isNull);
      expect(unstamped['calories'], isNull);
    });
  });
}

/// Minimal mirror of LocalRepositoryImpl.getToday() shaping (no DB).
Map<String, dynamic> _shapeToday(Map<String, dynamic> b) {
  final scalars = (b['scalars'] as Map).cast<String, dynamic>();
  num? sc(String k) => scalars[k] as num?;
  Map<String, dynamic> m(num? v, String tier) => {
    'value': v ?? '—',
    'confidence': v == null ? 0 : 0.8,
    'tier': tier,
    'inputs_used': const [],
  };
  return {
    'daily': {
      'readiness': m(sc('readiness'), 'HIGH'),
      'resting_hr': m(sc('rhr')?.round(), 'HIGH'),
      'strain': m(sc('trimp'), 'ESTIMATE'),
    },
    'sleep': const {},
    'hrv': {'rmssd': sc('rmssd'), 'sdnn': sc('sdnn')},
    'step_goal': 10000,
  };
}
