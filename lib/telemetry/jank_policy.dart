// jank_policy.dart — pure decision layer for the frame-jank watchdog.
//
// WHY THIS EXISTS (production bug, Crashlytics 0.9.19/0.9.20):
// The watchdog used to gate on `FrameTiming.totalSpan`, which is the span from
// the frame's vsync START to its raster END. That span includes time the engine
// was not doing any work at all — most importantly the gap across an app
// resume, where the "frame" straddles however long the app sat in the
// background. The result was reports like:
//
//     Slow frame: 16358ms (build=0 raster=8)
//
// i.e. a 16-SECOND "stutter" in which the app did 8 ms of actual work. That
// single false-positive class became the top issue by impacted-user count on
// both platforms, burying real signal underneath it.
//
// The honest measure of "the user saw a stutter" is the work the engine
// actually did on the frame: build (UI thread) + raster (GPU thread). Those are
// the two costs the app controls and the two a fix would move. `totalSpan` is
// still reported as CONTEXT — a large total with a small build+raster is
// interesting (scheduling delay, resume, thermal throttle), it is just not a
// jank report.
//
// Kept separate from TelemetryService so the rule is unit-testable without a
// SchedulerBinding, a Firebase app, or a real frame.

/// The verdict for one frame: should it be reported, and with what numbers.
class JankVerdict {
  const JankVerdict({
    required this.report,
    required this.workMs,
    required this.buildMs,
    required this.rasterMs,
    required this.totalMs,
  });

  /// True when this frame represents real engine work above the threshold.
  final bool report;

  /// build + raster — the cost the app is actually responsible for.
  final int workMs;

  final int buildMs;
  final int rasterMs;

  /// vsync-start → raster-end. Context only; never the trigger.
  final int totalMs;

  /// How much of the span was NOT engine work (scheduling delay, resume gap,
  /// throttling). Large values here with a small [workMs] are the signature of
  /// the false positive this policy exists to suppress.
  int get idleMs {
    final gap = totalMs - workMs;
    return gap > 0 ? gap : 0;
  }

  String get message =>
      'Slow frame: ${workMs}ms of engine work '
      '(build=$buildMs raster=$rasterMs, total span=${totalMs}ms)';
}

/// Pure jank rule. [thresholdMs] applies to build+raster, NOT to the total span.
///
/// The default of 700 ms is unchanged from the original watchdog, but it now
/// means "the engine burned 700 ms on one frame" rather than "700 ms elapsed",
/// which is roughly two orders of magnitude rarer and always actionable.
class JankPolicy {
  const JankPolicy({this.thresholdMs = 700});

  final int thresholdMs;

  JankVerdict evaluate({
    required int buildMs,
    required int rasterMs,
    required int totalMs,
  }) {
    // Defend against the negative/absurd durations a clock change or a
    // backgrounded engine can hand us — treat them as "no work observed"
    // rather than letting them underflow the sum into a false trigger.
    final b = buildMs > 0 ? buildMs : 0;
    final r = rasterMs > 0 ? rasterMs : 0;
    final work = b + r;
    return JankVerdict(
      report: work >= thresholdMs,
      workMs: work,
      buildMs: b,
      rasterMs: r,
      totalMs: totalMs > 0 ? totalMs : 0,
    );
  }
}
