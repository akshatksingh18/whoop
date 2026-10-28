// derive_pacing.dart — how hard to push per-day derivation, and how long to
// wait for it, depending on whether we are in the foreground or in a headless
// OS-granted background slot.
//
// WHY THIS EXISTS (production, Crashlytics 0.9.20 / iOS 27):
// `_runDayBlocksCancellable` was reporting `day_blocks_failed` —
// "TimeoutException: day-blocks computation timed out after 0:01:30" — from
// inside `IosBgTask._run`, i.e. only ever in BACKGROUND. Two foreground
// assumptions were being applied to a context that breaks both:
//
//  1. CONCURRENCY. Running 3 day-lanes concurrently is a win when there are
//     spare cores. A background task does not get spare cores — it gets a
//     throttled slice of CPU. Three lanes therefore do not go faster; they
//     divide one budget three ways and make each day ~3x slower in wall-clock.
//     Paired with a wall-clock timeout, that converts "3 days derived" into
//     "3 days timed out". Serial lanes also cap peak memory at one day's
//     substrate instead of three.
//
//  2. TIMEOUT. The 90 s guard exists to survive a HUNG day, but it is measured
//     in wall clock, and wall clock stops tracking work once the OS throttles
//     us. A day that computes in 20 s foreground can legitimately need several
//     times that in a BGProcessingTask on a busy or thermally-limited device.
//
// Kept pure and separate so the tuning is unit-testable without a database, an
// isolate, or a real background slot.

/// Pacing decisions for one derivation run.
class DerivePacing {
  const DerivePacing({required this.background});

  /// True for headless entries: iOS BGProcessingTask / BGAppRefreshTask,
  /// Android WorkManager, and the derive pass that follows a background drain.
  final bool background;

  /// Upper bound on foreground day-lanes. Deliberately conservative — this is
  /// a phone doing work alongside the UI, not a server batch job.
  static const int maxForegroundConcurrency = 3;

  static const Duration foregroundPerDayTimeout = Duration(seconds: 90);
  static const Duration backgroundPerDayTimeout = Duration(minutes: 4);

  /// Worker-pool size. [cores] is the device's processor count; pass whatever
  /// `Platform.numberOfProcessors` reported (callers that cannot read it should
  /// pass 1 and get the sequential fallback).
  int concurrency(int cores) {
    if (background) return 1;
    if (cores < 1) return 1;
    return cores < maxForegroundConcurrency ? cores : maxForegroundConcurrency;
  }

  /// Max wall-clock for ONE day's off-isolate compute. On timeout the day is
  /// skipped so the sweep always makes progress; the headline result still
  /// persists (partial) and stays un-finalized for a later retry.
  Duration get perDayTimeout =>
      background ? backgroundPerDayTimeout : foregroundPerDayTimeout;
}
