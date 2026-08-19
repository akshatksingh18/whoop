// TS-03 / TS-04 / TS-05 — the observed heart-rate ceiling and everything
// anchored on it, end to end.
//
// The chain each test walks:
//   compute  · `deriveDayBundle` bins the day's zones on the ceiling it was
//              handed and STAMPS which anchors it used (`zone_source`).
//   store    · `hr_ceiling_bpm` is a metric_series key, so "highest we've seen"
//              is a max over one small series rather than a bundle scan.
//   payload  · `getZones` serves the ceiling with its date + session, the edges
//              with the two numbers behind them, and the 28-day distribution.
//   screen   · gated: no measured anchors ⇒ NO distribution, not a caption.
//
// The gate is the point. A three-bar "you train too hard" built on 220−age is
// manufactured, so these tests assert the ABSENCE as hard as the presence.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/compute/hr_max.dart';
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

void main() {
  // ── TS-04 — one zone definition, and it says which anchors it used ─────────
  group('trainingZones', () {
    final rhr28 = List<double>.filled(28, 50);

    test('no observed ceiling ⇒ the age estimate, and it says so', () {
      final z = trainingZones(age: 30, deviceFamily: 'gen4')!;
      expect(z.source, 'tanaka');
      expect(z.maxHr, closeTo(187, 0.01)); // 208 − 0.7·30
      // %HRmax, unchanged from before TS-03: nobody's zones move until the
      // band has actually measured a ceiling on them.
      expect(z.zones.first.lower, closeTo(93.5, 0.01));
      expect(zonesAreMeasured(z.source), isFalse);
    });

    test('observed ceiling + 28 nights of resting HR ⇒ Karvonen %HRR', () {
      final z = trainingZones(
        age: 30,
        deviceFamily: 'gen4',
        observedCeilingBpm: 184,
        restingHrHistory: rhr28,
      )!;
      expect(z.source, 'karvonen');
      expect(z.maxHr, 184);
      // 50 + 0.50·(184−50) = 117, not 0.50·184 = 92.
      expect(z.zones.first.lower, closeTo(117, 0.01));
      expect(zonesAreMeasured(z.source), isTrue);
    });

    test('a very low resting HR widens zone 1 — arithmetic, not a bug', () {
      final z = trainingZones(
        observedCeilingBpm: 184,
        restingHrHistory: List<double>.filled(28, 40),
      )!;
      // Z1 STARTS at 112 instead of the 92 a %HRmax set would give, and every
      // band above it moves with it. This is the case the screen writes for.
      expect(z.zones.first.lower, closeTo(112, 0.01));
      expect(z.zones.first.upper - z.zones.first.lower, closeTo(14.4, 0.01));
    });

    test('measured ceiling but short resting history ⇒ %HRmax off the ceiling,'
        ' never Karvonen off a guess', () {
      final z = trainingZones(
        age: 30,
        deviceFamily: 'gen4',
        observedCeilingBpm: 184,
        restingHrHistory: List<double>.filled(
          ana.HeartRateZones.reserveMinDays - 1,
          50,
        ),
      )!;
      expect(z.source, 'observed');
      expect(z.zones.first.lower, closeTo(92, 0.01));
      // NOT measured for TS-05's purposes: only one of the two anchors is.
      expect(zonesAreMeasured(z.source), isFalse);
    });

    test('no AGE refuses; an unknown strap does not', () {
      // Tanaka is a population regression on age, not a calibration constant —
      // an unstamped strap gets the estimate, labelled as the estimate.
      expect(trainingZones(age: 30, deviceFamily: null)?.source, 'tanaka');
      // No age, no ceiling at all: nothing is substituted.
      expect(trainingZones(age: null, deviceFamily: 'gen4'), isNull);
      // …but a measured ceiling stands on its own: it did not come from a
      // per-family formula, so it does not need a calibrated family.
      expect(trainingZones(observedCeilingBpm: 184)?.source, 'observed');
    });
  });

  // ── one definition — a session's persisted split and its recomputed bands ──
  group('zoneMinutesFor', () {
    // 120 bpm for 120 minutes. On %HRmax off 187 that is Z2; on Karvonen off
    // 50/184 it is Z1. The persisted `zone_min` and the `zone_bands` the detail
    // screen recomputes both come off the SET, so they cannot land differently.
    final hr = List<int>.filled(120 * 60, 120);

    test(
      'the ceiling-only fallback is exactly the %HRmax bands it replaced',
      () {
        final fallback = zoneMinutesFor(hr, 187);
        final explicit = zoneMinutesFor(
          hr,
          0,
          zoneSet: ana.HeartRateZones.zonesFromMaxHr(187),
        );
        expect(fallback, explicit);
        expect(fallback[1], closeTo(120, 0.1)); // Z2
      },
    );

    test('a Karvonen set rebins the same heartbeats', () {
      final z = zoneMinutesFor(
        hr,
        187,
        zoneSet: trainingZones(
          observedCeilingBpm: 184,
          restingHrHistory: List<double>.filled(28, 50),
        ),
      );
      expect(z[0], closeTo(120, 0.1)); // Z1 now
      expect(z[1], 0);
    });

    test(
      'no set and no ceiling ⇒ an empty split, never five zeroes to draw',
      () {
        expect(zoneMinutesFor(hr, 0), isEmpty);
      },
    );
  });

  // ── TS-05 — the shape is a description, and it needs a clear largest share ──
  group('intensityShape', () {
    test('names the three shapes', () {
      expect(LocalRepositoryImpl.intensityShape(300, 60, 40), 'pyramidal');
      expect(LocalRepositoryImpl.intensityShape(300, 20, 80), 'polarised');
      expect(LocalRepositoryImpl.intensityShape(50, 200, 30), 'middle-heavy');
      expect(LocalRepositoryImpl.intensityShape(0, 0, 0), isNull);
    });
  });

  // ── compute — the day's zones are binned on what they were handed ─────────
  group('deriveDayBundle zone anchors', () {
    // A flat 6 h day at 120 bpm. Under the age estimate (187) that is 64% of
    // HRmax = Z2; under Karvonen off 184 with a 50 bpm rest it is 52% of
    // reserve = Z1. The SAME heartbeats, and the bundle has to say which
    // convention binned them.
    Map<String, dynamic> bundle({double? ceiling, int rhrDays = 28}) {
      const t0 = 1780000000;
      const n = 6 * 3600;
      return deriveDayBundle(
        DayBundleInput(
          date: '2026-06-01',
          dayTsSec: [for (var i = 0; i < n; i++) t0 + i],
          dayHr: List<int>.filled(n, 120),
          sleepTsSec: const [],
          sleepHr: const [],
          sleepRrTsMs: const [],
          sleepRrMs: const [],
          sleepSpo2Red: const [],
          sleepSpo2Ir: const [],
          sleepSkinTemp: const [],
          sleepJson: const {},
          hypnoStages: const [],
          sleepOnsetSec: 0,
          sleepOffsetSec: 0,
          profile: const {
            'age': 30,
            'sex': 'm',
            'weight_kg': 75,
            'height_cm': 178,
            'resting_hr': 50,
          },
          rhrHistory: List<double>.filled(rhrDays, 50),
          deviceFamily: 'gen4',
          observedHrCeilingBpm: ceiling,
        ).toJson(),
      );
    }

    test('no observed ceiling ⇒ tanaka, and the minutes land in Z2', () {
      final b = bundle();
      expect(b['zone_source'], 'tanaka');
      expect(b['zone_max_hr'], 187);
      expect((b['zones'] as Map)['z2'], greaterThan(300));
      expect((b['zones'] as Map)['z1'], 0);
    });

    test('an observed ceiling + resting history rebins the same day on %HRR', () {
      final b = bundle(ceiling: 184);
      expect(b['zone_source'], 'karvonen');
      expect(b['zone_max_hr'], 184);
      // 120 bpm is now Z1 (52% of reserve), not Z2.
      expect((b['zones'] as Map)['z1'], greaterThan(300));
      expect((b['zones'] as Map)['z2'], 0);
      // `max_hr_used` is DELIBERATELY untouched: TRIMP/calories are not moved
      // onto the observed ceiling here, because that re-scores every strain the
      // user has ever seen. The two ceilings on one screen are named, not
      // silently merged.
      expect(b['max_hr_used'], closeTo(187, 0.01));
    });

    test('the zone timeline is binned by the same set as the zone minutes', () {
      final tl = (bundle(ceiling: 184)['series'] as Map)['zone_timeline'];
      expect((tl as List), isNotEmpty);
      expect(tl.every((e) => (e as Map)['z'] == 1), isTrue);
    });
  });

  // ── payload — the ceiling, its attribution, and the TS-05 gate ────────────
  group('getZones', () {
    late LocalRepositoryImpl repo;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_hr_ceiling_zones_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      repo = LocalRepositoryImpl(getProfileMap: () => {'age': 30});
    });

    tearDown(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    Future<void> seedRhr(int days) async {
      for (var i = 0; i < days; i++) {
        await LocalDb.putMetricSeriesValue(
          '2026-05-${(i + 1).toString().padLeft(2, '0')}',
          'rhr',
          50,
        );
      }
    }

    /// A derived day carrying nothing but its strap stamp — the provenance the
    /// zone edges are named after. `decoded_onehz` is pruned at ~3 days, so the
    /// derived day is where it survives.
    Future<void> seedStampedDay({Map<String, dynamic> extra = const {}}) =>
        LocalDb.putDayResult(
          dayId: todayLabel(),
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({'device_family': 'gen4', ...extra}),
          windowJson: '{}',
          finalized: true,
        );

    test(
      'an unstamped install still gets the AGE-estimate zones',
      () async {
        await seedRhr(28);
        final z = await repo.getZones();
        // Provenance is still honestly unknown and still not claimed as gen4…
        expect(z['device_family'], isNull);
        // …but the bands are Tanaka on age, which no strap can move. This
        // screen used to be two paragraphs of copy and nothing else on every
        // real export, including a 287-day history.
        expect(z['source'], 'tanaka');
        expect(z['max_hr'], 187);
        expect(z['zones'], isNotEmpty);
        // The DISTRIBUTION still refuses: it needs measured anchors.
        expect(z['distribution'], isNull);
      },
    );

    test(
      'no ceiling series ⇒ age-estimate zones and NO distribution',
      () async {
        await seedRhr(28);
        await seedStampedDay();
        final z = await repo.getZones();
        expect(z['ceiling'], isNull);
        expect(z['source'], 'tanaka');
        expect(z['max_hr'], 187);
        // THE GATE. Not a chart with a caveat — nothing at all.
        expect(z['distribution'], isNull);
        // …and no resting anchor is claimed either, because these edges are not
        // built from one.
        expect(z['resting_hr'], isNull);
      },
    );

    test('the ceiling is the MAX of the series, with the day and session that '
        'set it', () async {
      await seedRhr(28);
      await LocalDb.putMetricSeriesValue('2026-08-01', 'hr_ceiling_bpm', 171);
      await LocalDb.putMetricSeriesValue('2026-08-03', 'hr_ceiling_bpm', 184);
      await LocalDb.putMetricSeriesValue('2026-08-09', 'hr_ceiling_bpm', 176);
      await seedStampedDay();
      // The day that set it carries the envelope with the session behind it.
      await LocalDb.putDayResult(
        dayId: '2026-08-03',
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'hr_ceiling': {
            'value': {
              'bpm': 184.0,
              'ts_ms': 0,
              'held_seconds': 22,
              'motion_g': 0.2,
            },
            'confidence': 1.0,
            'tier': 'high',
            'inputs_used': const ['hr_1hz'],
            'session_id': 's-1',
            'session_type': 'Running',
          },
        }),
        windowJson: '{}',
        finalized: true,
      );

      final z = await repo.getZones();
      final c = z['ceiling'] as Map;
      expect(c['bpm'], 184); // not 176, the most RECENT one
      expect(c['date'], '2026-08-03');
      expect(c['session_type'], 'Running');
      expect(c['held_seconds'], 22);
      // Both anchors measured ⇒ Karvonen, and the screen can print both.
      expect(z['source'], 'karvonen');
      expect(z['max_hr'], 184);
      expect(z['resting_hr'], 50);
      expect((z['zones'] as List).first, containsPair('lo', 117));
    });

    test(
      'measured anchors but too few sessions ⇒ still no distribution',
      () async {
        await seedRhr(28);
        await LocalDb.putMetricSeriesValue('2026-08-03', 'hr_ceiling_bpm', 184);
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        // Three sessions, each with a frozen per-minute trace. Real anchors, real
        // traces, and it still refuses: three workouts are not a pattern.
        for (var i = 0; i < 3; i++) {
          await LocalDb.putSession({
            'id': 'w-$i',
            'start_ts': now - (i + 1) * 86400,
            'end_ts': now - (i + 1) * 86400 + 1800,
            'type': 'run',
            'status': 'done',
            'device_family': 'gen4',
            'created_at': (now - (i + 1) * 86400) * 1000,
            'trace_json': jsonEncode({
              'hr': [
                for (var m = 0; m < 30; m++) {'t': m * 60, 'v': 150},
              ],
            }),
          });
        }
        expect((await repo.getZones())['distribution'], isNull);
      },
    );

    test('enough sessions with measured anchors ⇒ the distribution, described '
        'and not prescribed', () async {
      await seedRhr(28);
      await LocalDb.putMetricSeriesValue('2026-08-03', 'hr_ceiling_bpm', 184);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // 10 sessions: 40 easy minutes at 120 bpm (Z1 on %HRR off 50/184) and
      // 10 hard minutes at 175 bpm (Z5) each — polarised by construction.
      for (var i = 0; i < 10; i++) {
        await LocalDb.putSession({
          'id': 'w-$i',
          'start_ts': now - (i + 1) * 86400,
          'end_ts': now - (i + 1) * 86400 + 3000,
          'type': 'run',
          'status': 'done',
          'device_family': 'gen4',
          'created_at': (now - (i + 1) * 86400) * 1000,
          'trace_json': jsonEncode({
            'hr': [
              for (var m = 0; m < 40; m++) {'t': m * 60, 'v': 120},
              for (var m = 40; m < 50; m++) {'t': m * 60, 'v': 175},
            ],
          }),
        });
      }
      final d = (await repo.getZones())['distribution'] as Map;
      expect(d['sessions'], 10);
      expect(d['easy_min'], 400);
      expect(d['moderate_min'], 0);
      expect(d['hard_min'], 100);
      expect(d['shape'], 'polarised');
      expect((d['minutes'] as List)[0], 400);
    });

    test('a session outside the 28-day window is not counted', () async {
      await seedRhr(28);
      await LocalDb.putMetricSeriesValue('2026-08-03', 'hr_ceiling_bpm', 184);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < 10; i++) {
        await LocalDb.putSession({
          'id': 'old-$i',
          'start_ts': now - (40 + i) * 86400,
          'end_ts': now - (40 + i) * 86400 + 3000,
          'type': 'run',
          'status': 'done',
          'device_family': 'gen4',
          'created_at': (now - (40 + i) * 86400) * 1000,
          'trace_json': jsonEncode({
            'hr': [
              for (var m = 0; m < 50; m++) {'t': m * 60, 'v': 120},
            ],
          }),
        });
      }
      expect((await repo.getZones())['distribution'], isNull);
    });
  });
}
