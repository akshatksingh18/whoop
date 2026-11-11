// The real complete-night pipeline and its existing headline/diagnostic gate.
// Whole-night calculations are Linux-only; the named preflight is a short
// segmentation/admission check, not a local full analytics run.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/input_reuse.dart';
import 'package:whoop_companion/compute/onehz_pipeline.dart';
import 'package:whoop_companion/data/day_label.dart';

import 'coverage_derived_effort_handoff_test.dart' show authored;

void main() {
  late PreparedDerivationDay prepared;
  final cache = InputReuse(kAlgoVersion);
  setUpAll(() {
    DayClock.install([], []);
    prepared = prepareDerivationPayload(authored()).days.single;
  });

  test(
    'preflight readiness diagnostic fixture has a real qualifying main night',
    () {
      expect(prepared.sleepSub.length, greaterThanOrEqualTo(3 * 3600));
      expect(prepared.sleepJson['tst_sec'], greaterThanOrEqualTo(3 * 3600));
      expect(prepared.sleepSub.rrMs.length, greaterThanOrEqualTo(3 * 3600));
      expect(prepared.sleepOnsetSec, greaterThan(0));
      expect(prepared.sleepOffsetSec, greaterThan(prepared.sleepOnsetSec));
      expect(prepared.sleepSource, 'auto');
      expect(prepared.daySub.deviceFamily, 'gen4');
    },
  );

  for (final mode in ['positive-cap', 'negative-cap', 'clean', 'constant']) {
    test(
      'complete pipeline $mode keeps the headline and its explanation consistent',
      () {
        final history = [
          for (var i = 0; i < 28; i++)
            switch (mode) {
              'positive-cap' => 2.0 + i * .00001,
              'negative-cap' => 5.0 + i * .00001,
              'clean' => 3.0 + i * .05,
              _ => 3.0,
            },
        ];
        final d = DayBundleInput(
          date: prepared.date,
          dayTsSec: prepared.daySub.tsSec,
          dayHr: prepared.daySub.hr,
          dayRrTsMs: prepared.daySub.rrTsMs,
          dayRrMs: prepared.daySub.rrMs,
          sleepTsSec: prepared.sleepSub.tsSec,
          sleepHr: prepared.sleepSub.hr,
          sleepRrTsMs: prepared.sleepSub.rrTsMs,
          sleepRrMs: prepared.sleepSub.rrMs,
          sleepSkinTemp: prepared.sleepSub.skinTemp,
          sleepJson: prepared.sleepJson,
          hypnoStages: prepared.hypnoStages,
          sleepOnsetSec: prepared.sleepOnsetSec,
          sleepOffsetSec: prepared.sleepOffsetSec,
          sleepSource: prepared.sleepSource,
          profile: const {
            'age': 30,
            'sex': 'f',
            'weight_kg': 70,
            'height_cm': 170,
          },
          lnRmssdHistory: history,
          rhrHistory: [for (var i = 0; i < 28; i++) 50.0 + i],
          deviceFamily: 'gen4',
          dayConfidence: prepared.confidence,
          dayFlags: prepared.flags,
        );
        final before = jsonEncode(d.toJson());
        final bundle = deriveDayBundle(d.toJson(), reuse: cache);
        expect(jsonEncode(d.toJson()), before);
        final scalars = bundle['scalars'] as Map;
        final clinical = bundle['clinical'] as Map;
        // The cap must be reached by measured inputs,not by an absent-night gate.
        expect(scalars['rhr'], isA<num>());
        expect((clinical['resting_hr'] as Map)['value'], isA<Map>());
        expect((clinical['rmssd_sleep_session'] as Map)['value'], isA<num>());
        final composite = clinical['readiness_composite'] as Map;
        final diag = bundle['readiness_absent_diag'] as Map?;
        if (mode.endsWith('-cap')) {
          final value = composite['value'] as Map;
          expect(
            (value['composite_z'] as num).abs(),
            greaterThan(kReadinessZCap),
          );
          expect(
            value['score'],
            mode == 'positive-cap' ? greaterThan(99) : lessThan(1),
          );
          expect(scalars['readiness'], isNull);
          expect(diag, isNotNull);
          expect(diag!['note'], startsWith('unstable_baseline:z='));
          expect(diag['note'], contains('cap=5.0'));
          expect(diag['note'], isNot(contains('need_baseline')));
          for (final driver in ['hrv', 'rhr']) {
            expect(diag[driver], {'value': true, 'baseline_n': 28});
          }
          expect(diag['resp'], {
            'value': scalars['resp_rate'] != null,
            'baseline_n': 0,
          });
          expect(diag['temp'], {
            'value': false,
            'baseline_n': 0,
            'settled_frac': null,
          });
        } else if (mode == 'clean') {
          expect(scalars['readiness'], isA<num>());
          expect(scalars['readiness'], inInclusiveRange(1, 99));
          expect(diag, isNull);
        } else {
          expect(scalars['readiness'], isNull);
          expect(diag, isNotNull);
          expect(
            diag!['note'],
            isNot(startsWith('unstable_baseline:')),
            reason: 'missing usable drivers has its own earlier explanation',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
