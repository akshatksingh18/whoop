// headless_gate.dart — ONE process-wide gate for every headless sync entry point.
//
// Three separate wake paths can call runHeadlessSync():
//   - the iOS CoreBluetooth-restoration wake (IosBleRestore)
//   - the iOS BGProcessingTask (IosBgTask, heavy profile)
//   - the iOS BGAppRefreshTask (IosBgTask, sync-only profile)
//
// They used to carry their OWN private `_busy` flags with asymmetric guards, so
// two of them could race into runHeadlessSync() concurrently and only the
// engine's static band-owner arbitration saved the offload from duplicate ACKs.
// This gate makes the mutual exclusion EXPLICIT and shared: whichever entry
// point is running holds the gate; the others skip their cycle (a skipped wake
// is harmless — the non-destructive cursor catches everything up next time).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'band_ownership.dart';

class HeadlessSyncGate {
  HeadlessSyncGate._();

  static Future<void>? _running;
  static String? _runningOwner;

  /// True while any headless entry point holds the gate.
  static bool get busy => _running != null;

  // Skip-streak telemetry. Previously a collision between wake sources was
  // only ever a single debugPrint line with no counter — a wake source that
  // keeps losing the race EVERY cycle (a sign two sources are colliding
  // rather than actually diversifying background coverage, e.g. the
  // BLE-restore wake and a BGAppRefreshTask firing back-to-back every time)
  // looked identical to one that skipped once by chance. Per-owner
  // consecutive-skip + lifetime-total counters make that pattern observable.
  static final Map<String, int> _consecutiveSkipsByOwner = {};
  static int _totalSkips = 0;

  /// Consecutive skips at which a wake source stops being unlucky and starts
  /// being starved. Two colliding sources cost each other a cycle now and then;
  /// missing four in a row means the holder is not letting go.
  static const int starvedAfterSkips = 4;

  /// Hard ceiling on one headless run.
  ///
  /// [tryRun] used to `await body()` with nothing above it. The normal case is
  /// bounded — BleEngine.runHeadlessSync's own `awaitComplete` gives up after
  /// 600 s — but that bound is INSIDE the drain: an await in connect/disconnect
  /// that never completes parks the gate for the life of the process, and all
  /// four wake sources (BGProcessingTask, BGAppRefreshTask, the BLE-restore
  /// wake, the Android boot wake) then skip forever. Background sync stops with
  /// no crash and no log line, until the user relaunches.
  ///
  /// 15 min sits above the 600 s drain plus the heavy derive pass that follows
  /// it on a BGProcessingTask, so a run that hits this is wedged rather than
  /// slow. iOS will have killed the task long before, which is the point: the
  /// lease has to be released for the NEXT wake, whatever happened to this one.
  static const Duration runCeiling = Duration(minutes: 15);

  /// Consecutive skips for [owner] since it last actually ran (0 if it ran
  /// most recently, or has never skipped).
  static int consecutiveSkipsFor(String owner) =>
      _consecutiveSkipsByOwner[owner] ?? 0;

  /// Lifetime skip count across every owner (process-wide, resets on relaunch).
  static int get totalSkips => _totalSkips;

  /// True once [owner] has lost [starvedAfterSkips] cycles in a row.
  ///
  /// With [runCeiling] in place a holder cannot occupy the gate for more than
  /// 15 minutes, so a wake source that has missed four consecutive cycles is
  /// colliding with a peer every single time rather than skipping by chance —
  /// i.e. the two are firing together instead of diversifying coverage, which
  /// is the pattern the counters were added to make visible and which nothing
  /// had ever read.
  static bool isStarved(String owner) =>
      consecutiveSkipsFor(owner) >= starvedAfterSkips;

  /// Runs that hit [runCeiling]. Non-zero means a headless run wedged and was
  /// abandoned — the gate was handed back, the orphaned body was not stopped
  /// (nothing can stop an await that never completes).
  static int get timedOutRuns => _timedOutRuns;
  static int _timedOutRuns = 0;

  /// Run [body] exclusively. If another entry point already holds the gate the
  /// call is SKIPPED (returns null) — same "skip, don't queue" semantics the
  /// old per-flag guards had, but shared across all entry points.
  /// [ceiling] is injectable for tests; production uses [runCeiling].
  static Future<T?> tryRun<T>(
    String owner,
    Future<T> Function() body, {
    Duration? ceiling,
  }) async {
    if (_running != null) {
      final n = (_consecutiveSkipsByOwner[owner] ?? 0) + 1;
      _consecutiveSkipsByOwner[owner] = n;
      _totalSkips++;
      debugPrint(
        '[headless-gate] busy (held by "$_runningOwner") — "$owner" skipped '
        'this cycle (consecutive_skips=$n, total_skips=$_totalSkips)',
      );
      if (n == starvedAfterSkips) {
        // Deliberately once, at the crossing: a starved owner skips every
        // cycle, and a line per skip is a line nobody reads.
        debugPrint(
          '[headless-gate] STARVED — "$owner" has lost $n consecutive cycles '
          'to "$_runningOwner". Background coverage for "$owner" has stopped.',
        );
      }
      return null;
    }
    _consecutiveSkipsByOwner[owner] = 0; // this run breaks its own streak
    final done = Completer<void>();
    _running = done.future;
    _runningOwner = owner;
    try {
      // The ceiling is what makes a skip temporary. TimeoutException completes
      // the future we're awaiting, so the finally below runs and the gate is
      // handed back even though the orphaned body is still out there — an
      // abandoned run is recoverable (the cursor is non-destructive), a gate
      // held for the life of the process is not.
      return await body().timeout(ceiling ?? runCeiling);
    } on TimeoutException {
      _timedOutRuns++;
      debugPrint(
        '[headless-gate] "$owner" exceeded ${(ceiling ?? runCeiling).inMinutes} '
        'min and was abandoned — gate released (timed_out_runs=$_timedOutRuns)',
      );
      // The gate being handed back only lets the NEXT wake retry; it does not
      // by itself free the band. The three iOS entry points call
      // runHeadlessSync() with no lease, so it self-acquires one internally and
      // only the now-orphaned call frame holds that token — nothing else can
      // ever present it to BandOwnership.release(). Without this, one truly
      // wedged run leaves BandOwnership headless-owned for the rest of the
      // process: every later headless wake silently no-ops forever, and
      // acquireForeground()'s wait loop spins on a `_released` completer that
      // nothing left alive will ever complete. Force-clearing here mirrors
      // what headless_boot.dart already does explicitly for its own
      // caller-held lease on skip/timeout.
      BandOwnership.forceReleaseHeadless();
      return null;
    } finally {
      _running = null;
      _runningOwner = null;
      done.complete();
    }
  }

  /// Test-only reset — static state otherwise leaks across test cases.
  @visibleForTesting
  static void resetForTest() {
    _running = null;
    _runningOwner = null;
    _consecutiveSkipsByOwner.clear();
    _totalSkips = 0;
    _timedOutRuns = 0;
  }
}
