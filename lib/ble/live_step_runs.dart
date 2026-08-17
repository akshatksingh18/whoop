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
