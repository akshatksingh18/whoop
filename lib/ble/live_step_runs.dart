// live_step_runs.dart — pure, I/O-free: which SPANS of a live session the
// strap's 100 Hz pedometer actually saw walking. No BLE, no DB, no clock.
//
// WHY THIS EXISTS
// `live_coverage` used to get ONE row per connected session, spanning the whole
// wall-clock hull of the link (`deriveLiveCoverageWindow`, deliberately biased
// wide by `kCoverageDutyFloor`). That row answered "was a live link up", which
// was the right question while its job was to exclude minutes from a 1 Hz step
// ESTIMATE. That estimator is gone. The row's only remaining job is to say what
// the strap measured and WHEN — and for that a hull is a lie by omission:
// measured on the owner's own export for 2026-08-08, the band claimed 9.35 h of
// coverage for 216 steps (0.4 spm) while the phone had 11 h for 7,775 (11.8
// spm). Hand a per-window source ladder that hull and the day loses ~7,000
// steps — a different failure from whole-day precedence, the same size.
//
// So a span here is "the stream was delivering AND the pedometer counted",
// assembled from the same completed 60 s chunks the ingest path already runs
// `pedometer()` over. A chunk that counted nothing does not extend a run; the
// still hours between two walks are simply never claimed.
//
// SPAN LENGTH IS SAMPLED TIME, NEVER WALL TIME. A chunk covers `seconds` of
// signal however long it took to arrive: 60 s of samples dribbled in over three
// hours of a flaky link covers 60 s, not three hours. Over-claiming here would
// be the same bug in a smaller box.
//
// The counter itself is unchanged and stays where it is (analytics
// `pedometer`), and so is its gain — these runs carry the RAW count, and
// `StepParams.gain` is applied exactly once, at the moment a run is banked.

/// `live_coverage.source` for OUR OWN algorithm on the strap's 100 Hz IMU.
///
/// DISTINCT from `LocalDb.kStepSourceBand` ('band', which the NOOP importer
/// also writes) and from the gen5 on-chip counter (which never reaches this
/// table at all — it is read from `decoded_onehz.step_count`). A source ladder
/// cannot rank tiers it cannot tell apart.
const String kStepSourceStrap = 'strap_100hz';

// ── GATE 1: the strap may only count steps during GAIT ──────────────────────
//
// OXWALK_VALIDATION §1/§5: on a free-living wrist the counter's error is
// TWO-SIDED and unbounded above — worst over-count +199.5% (P18: 217 true steps
// read as 650), against +5.3% worst at the hip. Both 3x over-counters were
// low-ambulation hours, i.e. the wrist scored rhythmic ARM work as gait. A
// rowing, boxing, elliptical or lifting session is an hour of exactly that, and
// under a per-window source ladder the strap would win those windows outright
// and bank hundreds of steps nobody took.
//
// So a session that is not locomotion on foot contributes NO steps. It keeps HR,
// strain, zones and everything else; the phone covers those minutes instead. No
// active session at all is unchanged — passive wear still counts, which is the
// case the owner asked for ("when we get from strap is, when we get from strap").
//
// DERIVED-OR-PINNED, per the `kRouteTypeKeys` precedent: the catalogue has no
// gait flag to derive from (and `Track`/`gps` do not separate gait — Track.
// distance holds Rowing and Swimming, gps: true holds Cycling and Kayaking), so
// this set is PINNED against the catalogue by `gait_step_types_test.dart` in
// both directions. A key here that no activity can produce is the exact shape of
// the bug that left {'run','cycle','walk','hike'} matching nothing, ever.
//
// The set is deliberately TIGHT — foot locomotion with a free, gait-cadence arm
// swing, which is the only motion OxWalk measured:
//   * 'stairs' and 'stair_climber' are out — a hand on a rail damps the swing
//     and the corpus is level walking. Under-count risk only, but absent beats
//     wrong.
//   * 'sprinting', 'track_intervals', 'hurdles' are out — mostly standing
//     recovery, and sprint arm mechanics sit at the 5 steps/s ceiling of the
//     0.2-2.0 s interval guard rather than inside it.
// Widening it is one line plus a test edit; do that only with evidence.
const Set<String> kGaitStepTypeKeys = {
  'running',
  'trail_running',
  'walking',
  'hiking',
  'dog_walking',
  'treadmill',
  'cross_country',
};

/// True when a session of [type] is locomotion on foot, so the strap's
/// pedometer may count it. False for null — "no type" is not a gait type; the
/// caller decides separately what "no session at all" means.
bool isGaitStepType(String? type) =>
    type != null && kGaitStepTypeKeys.contains(type.toLowerCase());

// ── GATE 2: the stream must actually be fast enough to count ────────────────
//
// OXWALK_VALIDATION §4, decimating the 100 Hz wrist set:
//     100 Hz  MAPE 33.0%   50 Hz  33.6%   33 Hz  66.2%   25 Hz  90.8%
// The cliff sits between 50 and 33 Hz, and native 25 Hz reads MAPE 91.9% with
// NINE of 39 participants at exactly zero. The mechanism is that every constant
// in `pedometer` except the interval bounds is expressed in SAMPLES, so
// `window = 33` is 0.33 s at 100 Hz and 1.32 s at 25 Hz — wider than a whole
// gait cycle.
//
// 50 Hz is the floor because it is the last rate MEASURED to be indistinguishable
// from 100 Hz (33.6% vs 33.0%); the next step down doubles the error. Anything
// between them is unmeasured, so the floor sits on the last good measurement
// rather than in the middle of the cliff.
//
// This must be MEASURED, never assumed: `kLiveSampleRateHz = 100.0` and
// `_minuteSamples = 6000` rest on a `0x33` frame arrival rate that STEPS_ALGO §5
// records as documented nowhere in this tree and impossible to recover from any
// export (only historical `0x2f` records are archived; live frames are ephemeral
// by design). If `0x33` runs slow, the shipped counter loses 60-90% of the count
// silently.
const double kMinLiveSampleRateHz = 50.0;

/// Samples per wall-clock second actually achieved over a span — the measured
/// rate, not the assumed one.
///
/// Null when it cannot be measured (no span, no samples), which callers must
/// treat as "do not count": an unmeasurable window is exactly the one this gate
/// exists for. This also catches the gap `_magMin` cannot see — it concatenates
/// frames with no gap detection, discarding `ImuFrame.idx` and comparing no
/// inter-frame timestamps, so a dropped frame or a stalled link splices a hole
/// out and the state machine reads it as contiguous. A hole big enough to matter
/// drags the achieved rate under the floor and the window is refused; a hole too
/// small to move the rate is too small to move the count.
double? achievedSampleRateHz(int samples, int? startMs, int? endMs) {
  if (samples <= 0 || startMs == null || endMs == null || endMs <= startMs) {
    return null;
  }
  return samples * 1000 / (endMs - startMs);
}

/// One contiguous stretch of streamed signal in which the pedometer counted.
class LiveStepRun {
  const LiveStepRun(this.startTs, this.endTs, this.rawSteps);

  /// Epoch seconds in the BAND's record-time base — the same base
  /// `live_coverage` rows are compared in.
  final int startTs;
  final int endTs;

  /// PRE-gain count. See the file header.
  final int rawSteps;

  int get seconds => endTs - startTs;

  @override
  String toString() => 'LiveStepRun($startTs..$endTs, ${seconds}s, $rawSteps)';
}

/// Folds completed pedometer chunks into contiguous gait runs.
class GaitRuns {
  GaitRuns({this.maxRuns = 512});

  /// Ceiling on how many separate runs one connected session may hold — a bound
  /// on both memory and the session checkpoint that mirrors them. 512
  /// non-contiguous counting minutes is ~8.5 h of stop-start walking inside a
  /// single session.
  final int maxRuns;

  final List<LiveStepRun> _runs = [];

  List<LiveStepRun> get runs => List.unmodifiable(_runs);
  bool get isEmpty => _runs.isEmpty;
  void clear() => _runs.clear();

  /// Add one completed chunk: [rawSteps] counted over [seconds] of signal that
  /// ENDED at [endTs] (band base, epoch sec).
  ///
  /// A chunk with no steps is dropped rather than recorded — that is exactly
  /// what SPLITS one walk from the next, and a still minute is not coverage.
  /// [floorTs] is the session's first sampled second; a chunk is never allowed
  /// to claim signal from before it (the first chunk of a session ends slightly
  /// under 60 s after the first frame, because the frames carrying its samples
  /// took wall time to arrive).
  void addChunk({
    required int endTs,
    required int seconds,
    required int rawSteps,
    required int floorTs,
  }) {
    if (rawSteps <= 0 || seconds <= 0) return;
    var startTs = endTs - seconds;
    if (startTs < floorTs) startTs = floorTs;
    if (endTs <= startTs) return;
    if (_runs.isNotEmpty) {
      final last = _runs.last;
      // Contiguous with the run in progress (the ordinary case: back-to-back
      // counting minutes), or we are at the cap — either way extend instead of
      // appending.
      //
      // ponytail: at the cap this merges across a gap it should have kept, so a
      // pathological session over-claims one span. Raise `maxRuns` only if real
      // sessions ever get near it.
      if (startTs <= last.endTs || _runs.length >= maxRuns) {
        _runs[_runs.length - 1] = LiveStepRun(
          last.startTs,
          endTs > last.endTs ? endTs : last.endTs,
          last.rawSteps + rawSteps,
        );
        return;
      }
    }
    _runs.add(LiveStepRun(startTs, endTs, rawSteps));
  }
}
