// Session cadence from the band's live 100 Hz IMU stream.
//
// The step COUNT was already wired: `_ingestLiveMagsAt` runs the locked AN-2554
// `pedometer` over each completed 60 s chunk of live |a| samples. A completed
// chunk is one minute, so its step count IS a steps-per-minute reading — the
// cadence needs no second decode, no second stream and no second algorithm,
// only the right way to summarise the minutes that are already being counted.
//
// WHY A MEDIAN OF GATED MINUTES, not steps ÷ duration. A 45-minute session with
// ten minutes of walking in it has a mean of ~20 spm, which is not a cadence —
// it is not the cadence of the walking and it is not the cadence of the rest. A
// cadence is a property of ambulation, so only minutes that actually look like
// ambulation may contribute, and the median keeps one traffic-light minute from
// dragging the answer.
//
// CEILING. This is SESSION cadence off a LIVE stream. gen4's R10 is live-only,
// so there is no 24/7 cadence and no daily figure here — the daily step story
// stays with the phone pedometer. And it is cadence, not gait analysis: no
// stride length, no ground contact, no activity name.

import 'package:openstrap_analytics/onehz.dart' as ana;

/// A minute below this is not sustained walking (it is a few steps to the
/// kettle inside an otherwise still minute); above it is not walking either.
/// The same 60-200 spm band `livePedometer` treats as confident gait.
const int kMinCadenceSpm = 60;
const int kMaxCadenceSpm = 200;

/// At least this many gait-like minutes before we call it a cadence. One minute
/// is an anecdote, and a session that never really walked should report nothing
/// rather than a number built from its single busiest minute.
const int kMinCadenceMinutes = 3;

/// Session cadence (steps/min) from the per-minute RAW step counts the live
/// pedometer already produced, or null when the session did not walk enough to
/// have one.
///
/// [rawMinuteSteps] are pre-gain counts, exactly as `ana.pedometer` returns
/// them; the AN-2554 calibration gain is applied here so the gait gate is tested
/// against a real cadence rather than a raw one.
///
/// NULL IS THE ANSWER for a session with fewer than [kMinCadenceMinutes]
/// gait-like minutes. It is never 0 and never the mean of everything — an
/// indoor session that never walked has no cadence, and saying "0 spm" would
/// read as a measurement of stillness rather than an absence of walking.
int? sessionCadenceSpm(List<int> rawMinuteSteps) {
  final gait = <int>[
    for (final raw in rawMinuteSteps)
      if (raw > 0)
        if ((raw * ana.StepParams.gain).round() case final spm
            when spm >= kMinCadenceSpm && spm <= kMaxCadenceSpm)
          spm,
  ];
  if (gait.length < kMinCadenceMinutes) return null;
  gait.sort();
  final mid = gait.length ~/ 2;
  // Even count: mean of the two middle minutes, rounded — cadence is reported
  // as a whole number of steps per minute.
  return gait.length.isOdd
      ? gait[mid]
      : ((gait[mid - 1] + gait[mid]) / 2).round();
}
