// A resting heart rate is nocturnal or it is absent.
//
// `scalars.rhr` used to fall back to the whole DAY's HR when no sleep was
// scored, and the fallback was published as the resting heart rate: it drives
// the Heart card and chart, it is the `metric_series` key the personal baseline
// folds, and it is what HealthKit receives.
//
// MEASURED, on the owner's own export (17 days, 671,847 1 Hz rows). His fifteen
// full-wear nights read 55.7–64.2 bpm. 2026-07-31 was worn 213 minutes with no
// night scored at all, and published 88.0 bpm as a resting heart rate — a
// 24-30 bpm error rendered as a measurement. A second export published 116.7
// the same way. There is no tier at which "the quietest half hour of a day
// spent awake" is a resting heart rate; it is a different quantity wearing the
// label, so the only honest output is absence with its reason.
//
// The gate lived one level too high before this: v47 moved READINESS onto the
// nocturnal-only `rhr_nocturnal` and left the charted `rhr` on the fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

const int _t0 = 1786700000;

/// A day like 2026-07-31: 213 minutes of wear, awake throughout, HR sitting in
/// the high 80s. [scoredSleep] adds a real sleep window over the same seconds.
Map<String, dynamic> _bundle({required bool scoredSleep}) {
  const wornSec = 213 * 60;
  final ts = <int>[for (var i = 0; i < wornSec; i++) _t0 + i];
  // Awake HR: never below 86, so any daytime-derived "trough" is unmistakably
  // not a resting rate.
  final hr = <int>[for (var i = 0; i < wornSec; i++) 88 + (i % 11)];
  final zeros = List<int>.filled(wornSec, 0);
  return deriveDayBundle(
    DayBundleInput(
      date: '2026-07-31',
      dayTsSec: ts,
      dayHr: hr,
      sleepTsSec: scoredSleep ? ts : const [],
      sleepHr: scoredSleep ? hr : const [],
      sleepRrTsMs: const [],
      sleepRrMs: const [],
      sleepSpo2Red: scoredSleep ? zeros : const [],
      sleepSpo2Ir: scoredSleep ? zeros : const [],
      sleepSkinTemp: scoredSleep ? zeros : const [],
      sleepJson: scoredSleep
          ? <String, dynamic>{'tst_sec': wornSec, 'efficiency_pct': 90.0}
          : <String, dynamic>{},
      hypnoStages: const [],
      sleepOnsetSec: scoredSleep ? ts.first : 0,
      sleepOffsetSec: scoredSleep ? ts.last + 1 : 0,
      profile: const {'age': 30, 'sex': 'm', 'weight_kg': 70, 'height_cm': 175},
      deviceFamily: 'gen4',
    ).toJson(),
  );
}

void main() {
  test('a day with no scored sleep publishes no resting HR', () {
    final b = _bundle(scoredSleep: false);
    final scalars = (b['scalars'] as Map).cast<String, dynamic>();

    // The number this day used to publish was ~88 bpm, from the same 1 Hz HR.
    expect(scalars['rhr'], isNull);
    // ONE resting HR: the two keys are the same value, always.
    expect(scalars['rhr_nocturnal'], scalars['rhr']);

    // Absent WITH ITS REASON, never a bare dash and never a guess.
    final rhr = ((b['clinical'] as Map)['resting_hr'] as Map)
        .cast<String, dynamic>();
    expect(rhr['value'], anyOf(isNull, '—'));
    expect(rhr['note'] as String, contains('no sleep was scored'));
    expect(rhr['tier'], isNotNull);

    // The baseline series must not fold it either — that is what widened the
    // personal spread and pushed mdc() out of reach.
    final baseline = ((b['baselines'] as Map)['resting_hr'] as Map)
        .cast<String, dynamic>();
    expect(baseline['value'], isNull);
  });

  test('the same day WITH a scored night still publishes one', () {
    final scalars =
        (_bundle(scoredSleep: true)['scalars'] as Map).cast<String, dynamic>();
    expect(scalars['rhr'], isNotNull, reason: 'gated on sleep, not disabled');
    expect(scalars['rhr_nocturnal'], scalars['rhr']);
  });
}
