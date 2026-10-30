// DerivationEngine — the on-device compute COORDINATOR (MAIN ISOLATE).
//
// Current flow (per trigger):
//   1. Decide WHICH calendar days need compute (force / pending span / latest
//      freshness-critical day).
//   2. Build / refresh the first primitive, `sleep_session_candidates`, from a
//      bounded overlap window only when needed.
//   3. Load the exact calendar-day substrate + exact sleep-window substrate for
//      the target day, then build one PreparedDerivationDay from those pieces.
//   4. Run the pure day pipeline off-isolate, then compute the second
//      primitive, `wake_day_features`, directly from the local-day substrate.
//   5. Persist day_result as the materialized UI surface, plus compact baseline
//      artifacts (`rolling_artifact`, `crossday_input`) for downstream reuse.
//   6. Run cross-day / notifications from those compact artifacts and prune raw
//      only after a force/full-history sweep, never before derived.
//
// Finalized-day rescans are still allowed for baseline-dependent scalars
// (readiness/recovery, illness/anomaly, stress), but they now gate off the
// rolling baseline artifact instead of recomputing the signature ad hoc from
// metric_series each time.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;

import 'strain_backfill.dart' show backfillStrainScale;

import 'package:flutter/foundation.dart';
import 'findings.dart';
import 'nap_edits.dart';
import 'package:whoop_analytics/onehz.dart' as ana;

import '../data/db.dart';
import '../data/nap_ledger.dart';
import '../data/day_label.dart';
import '../data/day_zone_store.dart';
import '../data/series_codec.dart';
import '../notify/fired_keys.dart';
import '../notify/notification_center.dart';
import '../notify/notification_event.dart';
import '../notify/notification_prefs.dart' show NotificationPrefs;
import '../notify/tap_router.dart' show workoutSuggestionRoute;
import 'crossday_pipeline.dart';
import 'derive_pacing.dart';
import 'hr_max.dart'
    show estimatedMaxHr, smoothedMaxHr, smoothedMinHr, trainingZones;
import 'movement_floor_policy.dart' as mfp;
import 'sleep_profile_policy.dart';
import 'derive_prepare.dart';
import 'onehz_pipeline.dart';
import 'input_reuse.dart';
import 'step_cadence.dart';
import 'manual_session.dart' show kCaloriesBasisActive;
import 'profile.dart';
import 'readiness_explain.dart' show recoveryExplanationSnapshot;
import 'substrate.dart';

/// Current analytics/bundle baseline. Any output change needs a reviewed bump
/// and changelog entry here so immutable persisted days do not masquerade as
/// results of another algorithm.
/// Version 100: the approved R10 decoder repair accepts up to eight plausible
/// intervals in historical/shared-lite decoding, matching the existing realtime
/// limit. More retained beat input can affect derived HRV/readiness; scientific
/// coefficients, minimum-input gates and schema remain unchanged. Missing old
/// bytes are not reconstructed, and no blanket archive replay is introduced.
///
/// Detailed earlier version decisions and private reference observations remain
/// in the pre-fresh-start local archive. Current scientific methods are documented
/// beside their implementations and in packages/analytics/ALGORITHMS.md.
const int kAlgoVersion = 100;

// In-tree source/path identities and the algorithm version are guarded by
// packages/algorithm-contract.json and tool/algorithm_contract.py. A digest
// update requires output/version review; it does not prove numerical validity.

// Fold idempotency, the minimum-nights warm-up, and legacy-payload handling
// all live in SleepProfilePolicy (pure, unit-tested) — see
// lib/compute/sleep_profile_policy.dart for the evidence behind each rule.

/// Raw is kept this many days past derivation, then pruned (derived stays).
const int rawRetentionDays = 3;

/// A day stays recomputable for this long after its wake, then FINALIZES (locks)
/// — more flash may still drain within this buffer (ARCHITECTURE_V2: ~48 h).
const int _finalizationSec = 48 * 3600;

/// How many trailing derived days feed readiness/composite baselines.
const int _baselineWindowDays = 28;

/// Readiness is meant to be a stable MORNING score, but a day stays recomputable
/// for ~48 h (`_finalizationSec`) and every re-derive overwrites the persisted
/// readiness scalar. As the night's flash finishes draining and the trailing
/// 28-day baseline shifts, the surfaced value legitimately drifts through the
/// day (#128: "morning it was 49, now 45"). Once today's overnight is genuinely
/// COMPLETE we PIN the first such readiness as the headline so it stops moving.
///
/// "Complete" must be stronger than `overnight_state == 'ready'` — that flips as
/// soon as the FIRST sleep-bearing row lands (mid-drain), so pinning on it could
/// freeze a partial-night value. We instead require the drained data edge to
/// have moved at least this far PAST the sleep offset (wake): the whole sleep
/// window is then decoded and the segmentation-placed wake is settled, so the
/// overnight inputs are final. Same "edge past the window" model finalisation
/// uses, anchored at wake+margin rather than wake+48 h. Conservative but still
/// reached within the first post-wake sync in practice; raise it to trade a
/// slightly later freeze for more safety margin.
const int _headlineFreezeMarginSec = 60 * 60;

/// The frozen morning readiness headline that should be persisted/surfaced for
/// [today], given the current pin and a fresh look at today's live readiness and
/// whether today's overnight is genuinely COMPLETE. Pure so the freeze semantics
/// are unit-tested without the derive/DB machinery.
///
/// - Not yet a complete overnight → no pin (the headline tracks the live value).
/// - First complete overnight → pin the live value.
/// - Later same-day looks → keep the FIRST pin (the whole point: no daytime
///   drift — a re-derive that would RAISE or LOWER the score is ignored).
/// - A new day → the prior day's pin no longer applies; re-pins once the new
///   day's overnight completes.
@visibleForTesting
({String day, int value})? nextFrozenHeadline({
  required String today,
  required bool overnightComplete,
  required int? liveReadiness,
  required ({String day, int value})? current,
}) {
  if (current != null && current.day == today) return current; // pinned; hold
  if (overnightComplete && liveReadiness != null) {
    return (day: today, value: liveReadiness); // first complete settle → pin
  }
  return null; // nothing to pin yet for today
}

/// Test seam: the rolling baseline window the readiness computation actually
/// runs against, loaded exactly as production does. Exposed to assert the read
/// path ignores a polluted `rolling_artifact` and rebuilds from `metric_series`.
@visibleForTesting
Future<List<double>> debugBaselineWindow(String key) async =>
    (await _BaselineHistoryCache.load()).values(key);

/// Test seam: the EXACT per-day baseline windows one derivation sweep would feed
/// the readiness pass, in dispatch order (`orderedDays` is newest-first).
///
/// Pins the two properties the sweep path must have — the snapshot is loaded
/// ONCE and never mutated as days complete, and each day's window self-excludes
/// that day's own date. Both were violated by the old `appendScalars` sweep.
@visibleForTesting
Future<List<List<double>>> debugSweepBaselineWindows(
  String key,
  List<String> orderedDays,
) async {
  final history = await _BaselineHistoryCache.load();
  return [for (final day in orderedDays) history.valuesBefore(key, day)];
}

@visibleForTesting
({List<String> days, String reason}) selectLightDeriveDays({
  required Set<String> rawDays,
  required List<String> pendingDays,
  required String today,
}) {
  if (rawDays.contains(today) && pendingDays.contains(today)) {
    return (days: [today], reason: 'today-priority');
  }
  return (days: [pendingDays.last], reason: 'latest-pending');
}

class _DeriveScope {
  final bool fullHistory;
  final List<String> targetDays;
  final String reason;

  /// EVERY day label that still has 1 Hz substrate on disk — not just the ones
  /// this pass targets. The raw-prune guard needs the whole set: a day that
  /// aged out of the light scope while still un-derived is exactly the day
  /// whose raw must not be deleted, and it is by definition not in
  /// [targetDays]. Comes free from the `decodedRecTsMaxByDay()` that selects
  /// the scope, so nothing extra is queried for it.
  final List<String> rawDays;

  const _DeriveScope({
    required this.fullHistory,
    required this.targetDays,
    required this.reason,
    this.rawDays = const [],
  });
}

/// One (date, value) sample of a baseline series.
typedef _DatedValue = ({String date, double value});

class _BaselineHistoryCache {
  _BaselineHistoryCache(this._series);

  /// The baseline series this cache carries, keyed by `metric_series.key`.
  static const List<String> keys = [
    'ln_rmssd',
    'ln_rmssd_v2',
    'rmssd',
    'rhr',
    'resp_rate',
    'skin_temp_adc',
    'readiness',
    // Nightly total sleep (minutes) — the readiness sleep input's baseline.
    'tst_min',
    // Per-day high quantile of the calibration-invariant dynamic accel
    // amplitude. The 1 Hz activity estimator's floor is anchored on the MEDIAN
    // of this series across trailing days, never on a same-day value: a
    // single-day threshold collapses on a quiet day and passes everything,
    // which is the mirror image of the absolute-constant failure it replaced.
    'dyn_p90',
    // TS-03 — the per-day OBSERVED heart-rate ceiling (bpm). Not a baseline
    // like the rest: nothing is z-scored against it and it is never averaged.
    // It rides in this cache because it is a `metric_series` key the day's
    // derive needs the PRIOR days' values of, which is exactly what this
    // snapshot is (see [maxBefore]).
    'hr_ceiling_bpm',
  ];

  /// DATED baseline samples, ascending by date, one entry per day (metric_series
  /// is keyed `(date, key)` with REPLACE, so it is structurally de-duplicated).
  ///
  /// IMMUTABLE for the lifetime of one derivation sweep. There is deliberately
  /// no mutator: the previous `appendScalars` mutated this shared snapshot as
  /// each day of a sweep finished, which re-introduced exactly the duplicate-day
  /// pollution the load path was rewritten to prevent — `load()` had ALREADY
  /// read the persisted values of the days about to be re-derived, so appending
  /// each finished day again (and evicting a real old day to stay at 28) left
  /// later days in the sweep reading a window with up to 21 duplicated recent
  /// values in descending date order. Median/MAD then collapsed toward the
  /// repeated value and readiness went blank/wrong — the load-path bug, moved
  /// into the sweep path. A sweep now reads ONE frozen snapshot, and each day
  /// derives its own window from it by date.
  final Map<String, List<_DatedValue>> _series;

  /// Load the rolling baseline window that feeds the readiness/illness
  /// computations. This ALWAYS rebuilds from `metric_series` — the canonical
  /// scalar store, keyed `(date, key)` with REPLACE, so it is structurally one
  /// value per day.
  ///
  /// We deliberately do NOT trust the persisted `rolling_artifact` for history.
  /// That artifact was written from an in-memory cache with no day identity, so
  /// repeated same-day re-derives could stack duplicate copies of today into the
  /// window; once enough slots matched, the readiness composite's robust z-score
  /// hit MAD=0 and went absent — the blank readiness ring. A polluted artifact
  /// is still valid JSON, so trusting it on read would let that pollution reach
  /// the computation on the first post-upgrade derive (and, when every day is
  /// finalized and `run()` does no work, forever). Rebuilding from the
  /// de-duplicated store on every load makes the read path immune and self-heals
  /// any already-polluted install.
  ///
  /// NOTE ON THE QUERY: `LocalDb.metricSeries(key)` with NO `limit` is the whole
  /// series, `date ASC` — the dates are what make a per-day `date < target`
  /// window possible at all. It must NOT be given a `limit` (that is `date ASC
  /// LIMIT n`, i.e. the OLDEST n — the opposite of a trailing window); the
  /// trailing window is taken here, in Dart, per target day.
  ///
  /// IMPORTED DAYS ARE EXCLUDED. `LocalDb.isMeasuredDay` kept another vendor's
  /// export from OVERWRITING a measured day, but nothing kept it out of the
  /// window on the way back in: a WHOOP or cloud import writes real
  /// `metric_series` rows for `rhr`, `rmssd`, `readiness` and `resp_rate`, and
  /// this load read them like any other day. Their scores are a different
  /// algorithm's output over a different (or no) substrate, so blending them in
  /// moves the median every personal z-score is taken against — silently, for
  /// as long as the window is, and worst exactly when someone imports their
  /// history on day one and has nothing else in the window at all.
  ///
  /// The mask is taken ONCE per load and applied to every key, because the
  /// query behind it scans day bundles (see [LocalDb.importedDates]).
  ///
  /// A SECOND, NARROWER MASK rides along: days measured by a different BAND
  /// FAMILY, applied only to [LocalDb.familySeamKeys]. That one is not about a
  /// foreign algorithm — it is this app's own maths over a sensor whose units
  /// differ (`skin_temp_adc` is a gen4 ADC count on one side of a strap swap
  /// and a gen5 centi-degree on the other), so it is masked PER-METRIC rather
  /// than blanket: a family seam that only makes a number noisier (RHR, RMSSD)
  /// stays in the window. Empty for a user who has never changed generation,
  /// which is why it moves no number today.
  static Future<_BaselineHistoryCache> load() async {
    final imported = await LocalDb.importedDates();
    final foreignFamily = await LocalDb.foreignFamilyDates();
    Future<List<_DatedValue>> hist(String key) async {
      final rows = await LocalDb.metricSeries(key);
      final seam = LocalDb.familySeamKeys.contains(key)
          ? foreignFamily
          : const <String>{};
      final out = <_DatedValue>[];
      for (final row in rows) {
        final date = row['date'];
        final value = row['value'];
        if (date is! String || date.isEmpty || value is! num) continue;
        if (imported.contains(date) || seam.contains(date)) continue;
        out.add((date: date, value: value.toDouble()));
      }
      return out;
    }

    final loaded = await Future.wait([for (final k in keys) hist(k)]);
    return _BaselineHistoryCache({
      for (var i = 0; i < keys.length; i++) keys[i]: loaded[i],
    });
  }

  /// The trailing [_baselineWindowDays] values for [key], oldest→newest.
  ///
  /// This is the WHOLE window including the newest day; it backs the persisted
  /// rolling artifact + the rescan signature, which describe "the baseline as it
  /// currently stands". Per-day derivation must use [valuesBefore] instead.
  List<double> values(String key) => _trailing(_series[key] ?? const []);

  /// The trailing [_baselineWindowDays] values for [key] STRICTLY BEFORE
  /// [beforeDate] (`date < ?`), oldest→newest — the baseline for deriving the
  /// day labelled [beforeDate].
  ///
  /// SELF-EXCLUSION IS THE POINT. The previous derive of the same day has
  /// already written its own row to `metric_series`, so an unfiltered trailing
  /// window contained TODAY: every light pass after the first z-scored today's
  /// RHR/HRV/temp against a baseline that already contained today (pulling the
  /// baseline toward the value under test and understating a genuinely
  /// off day), and the lnRMSSD stack — which is contractually handed
  /// `[...history, today]` and takes all-but-last as its baseline — counted it
  /// a second time. v38 fixed precisely this self-inclusion inside analytics;
  /// this is the same defect at the edge layer that feeds it. Dates strictly
  /// AFTER the target are excluded too: a baseline is prior days, and a backfill
  /// sweep must not let later days leak into an older day's baseline (which
  /// would also make the result depend on sweep order).
  /// The set of dates that actually have a stored value for [key].
  ///
  /// Used to detect wear GAPS: a date with no `dyn_p90` row means the band
  /// produced no usable motion that day.
  Set<String> datesFor(String key) => {
    for (final s in _series[key] ?? const <_DatedValue>[]) s.date,
  };

  /// The LARGEST value of [key] over every stored day strictly before
  /// [beforeDate], or null when there is none.
  ///
  /// Deliberately NOT windowed to the trailing 28 like [valuesBefore]: this
  /// backs "highest we've seen", and a ceiling that silently drops out of the
  /// window would move every zone boundary in the app with nothing on screen
  /// saying why. The date it happened is shown next to it, so an old one is
  /// visible rather than anonymous.
  double? maxBefore(String key, String beforeDate) {
    double? best;
    for (final s in _series[key] ?? const <_DatedValue>[]) {
      if (s.date.compareTo(beforeDate) >= 0) continue;
      if (best == null || s.value > best) best = s.value;
    }
    return best;
  }

  /// B88-11: the last 28 eligible values, but only from the 60 calendar days
  /// before [beforeDate], so a long wear gap never compares a night against a
  /// months-old baseline (an honest warm-up follows instead).
  List<double> valuesBefore(String key, String beforeDate) {
    final d = DateTime.parse(beforeDate);
    final from = DateTime(d.year, d.month, d.day - _baselineMaxAgeDays);
    final fromLabel =
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')}';
    return _trailing([
      for (final s in _series[key] ?? const <_DatedValue>[])
        if (s.date.compareTo(beforeDate) < 0 &&
            s.date.compareTo(fromLabel) >= 0)
          s,
    ]);
  }

  static const int _baselineMaxAgeDays = 60;

  static List<double> _trailing(List<_DatedValue> samples) {
    final from = samples.length <= _baselineWindowDays
        ? 0
        : samples.length - _baselineWindowDays;
    return [for (var i = from; i < samples.length; i++) samples[i].value];
  }

  Map<String, dynamic> toArtifactJson() {
    double? avg(List<double> xs) {
      if (xs.isEmpty) return null;
      return xs.reduce((a, b) => a + b) / xs.length;
    }

    String fmt(double? v) => v == null ? 'na' : (v * 100).round().toString();
    final rhr = values('rhr');
    final rmssd = values('rmssd');
    final temp = values('skin_temp_adc');
    final resp = values('resp_rate');
    final readiness = values('readiness');
    final signature =
        'v$kAlgoVersion|n${rhr.length}|rhr${fmt(_median(rhr))}|rmssd${fmt(_median(rmssd))}'
        '|temp${fmt(_median(temp))}|resp${fmt(_median(resp))}';
    return {
      'algo_version': kAlgoVersion,
      'signature': signature,
      'series': {
        'ln_rmssd': values('ln_rmssd'),
        'rmssd': rmssd,
        'rhr': rhr,
        'resp_rate': resp,
        'skin_temp_adc': temp,
        'readiness': readiness,
      },
      'rolling': {
        'rhr': avg(rhr),
        'rmssd': avg(rmssd),
        'readiness': avg(readiness),
        'n': rhr.length,
      },
    };
  }
}

/// Background re-trigger window: how far back from the DATA EDGE a
/// baseline-dirty rescan re-derives days (including finalized ones). Kept ≤ the
/// raw-retention window so every day in scope still has raw to re-derive from;
/// older days simply aren't in the substrate and are naturally excluded.
const int _rescanWindowDays = 21;

/// Per-day-local page/row accumulator for the prepare stage (see
/// `_prepareTargetDay`/`_loadSubstrateRange`). Deliberately NOT shared
/// `_diag` state — under concurrent per-day processing, multiple days
/// resetting/incrementing the same shared counters would race and produce
/// garbage diagnostics. Each day gets its own instance; only the final
/// per-day total is merged into the shared running max, once.
class _PrepareStats {
  int pages = 0;
  int rows = 0;
}

/// Calculation stopped on purpose — the app went to the background, or iOS
/// is ending a wake it granted. Not a failure: no day is marked skipped, no
/// success stamp is written, and the scheduler requeues the job (build 86).
class DeriveCancelled implements Exception {
  const DeriveCancelled(this.reason);
  final String reason;
  @override
  String toString() => 'derive cancelled ($reason)';
}

/// The one process-wide stop for derivation. [request] bumps a generation:
/// every running pass that started under an older generation stops at its
/// next check, and every in-flight compute isolate is killed at once rather
/// than left burning CPU into an iOS background kill (B86 background repair).
class DeriveStop {
  DeriveStop._();
  static int _generation = 0;
  static String _reason = '';
  static final StreamController<int> _changes = StreamController<int>.broadcast(
    sync: true,
  );

  static int get generation => _generation;
  static Stream<int> get changes => _changes.stream;

  static void request(String reason) {
    _generation++;
    _reason = reason;
    _changes.add(_generation);
  }

  /// Throws [DeriveCancelled] when a stop arrived after [since].
  static void check(int since) {
    if (_generation != since) throw DeriveCancelled(_reason);
  }

  static DeriveCancelled get error => DeriveCancelled(_reason);
}

/// Run [worker] over [items] with at most [concurrency] running at once. Each
/// of up to [concurrency] "lanes" pulls the next unclaimed item as soon as
/// it's free — a mix of fast (empty/mostly-empty day) and slow (heavy
/// backlog day) items keeps every lane continuously busy, rather than
/// lock-stepping in fixed-size batches where one slow item stalls an entire
/// batch. Pure orchestration: no DB/isolate awareness of its own — every
/// caller in this file catches errors INSIDE [worker] itself (a day that
/// fails is marked skipped and processing continues), so a throwing [worker]
/// is not part of the normal contract here, but note that (per
/// `Future.wait`'s default behavior) an uncaught throw would propagate out
/// and NOT stop already-in-flight sibling lanes from completing their
/// current item first.
///
/// This is the ONE place run()/runDays()/rescanRecent() get their real,
/// multi-core parallelism from — replacing what used to be a fully
/// sequential `for` loop that left every core but one idle during a
/// multi-day backlog sweep.
@visibleForTesting
Future<void> runWithConcurrency<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) worker,
) async {
  if (items.isEmpty) return;
  final poolSize = math.min(concurrency, items.length).clamp(1, items.length);
  var nextIndex = 0;
  Future<void> lane() async {
    while (true) {
      final myIndex = nextIndex;
      if (myIndex >= items.length) return;
      nextIndex++; // no `await` since the read above — atomic claim
      await worker(items[myIndex]);
    }
  }

  await Future.wait(List.generate(poolSize, (_) => lane()));
}

/// Minimal async mutex: serializes read-modify-write sections that concurrent
/// day workers ([runWithConcurrency]) would otherwise interleave.
///
/// Dart's scheduler makes a single statement atomic, but NOT a
/// read → decide → write sequence with `await`s in it: every lane can observe
/// the pre-write state before any of them writes. The shared movement floor is
/// exactly that shape, so it needs one.
class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}

class DerivationEngine {
  DerivationEngine({this.log, this.background = false, this.onSessionChanged});

  /// Called only on the DB-owning isolate after a deferred session write.
  final void Function()? onSessionChanged;
  final void Function(String)? log;

  /// True when this engine was constructed inside a headless/background entry
  /// (iOS BGProcessingTask / BGAppRefreshTask, Android WorkManager, the
  /// post-drain background sync pass). The OS throttles CPU hard in those
  /// contexts, which changes two tuning decisions — see [_deriveConcurrency]
  /// and [_perDayTimeout]. Set at construction, not per-run, so a long-lived
  /// foreground engine can never inherit background tuning by accident.
  final bool background;

  /// PROCESS-WIDE, not per-engine. The thing it protects is the DATABASE, and
  /// there is one of those however many engines exist — but engines are built
  /// per call site (`lib/sync/background_sync.dart` constructs a fresh one for
  /// every headless wake), so an instance flag guarded nothing across them. Two
  /// passes could then derive the same day at once, and `partial`/`finalized`
  /// are decided before the write transaction, so the slower one's PARTIAL row
  /// could land on top of the faster one's complete row.
  static bool _running = false;
  static final _inputReuse = <String, InputReuse>{};
  bool get running => _running;

  /// Run [body] under the process-wide derivation lock, returning [busy]
  /// unchanged if a pass is already in flight. Only for entry points that do
  /// NOT call another locked entry point (which would deadlock-by-skip).
  static Future<T> _withRunLock<T>(T busy, Future<T> Function() body) async {
    if (_running) return busy;
    _running = true;
    try {
      return await body();
    } finally {
      _running = false;
    }
  }

  final Map<String, dynamic> _diag = {
    'running': false,
    'stage': 'idle',
    'mode': null,
    'force': false,
    'started_at': null,
    'finished_at': null,
    'duration_ms': null,
    'raw_pages': 0,
    'raw_rows': 0,
    'max_day_raw_pages': 0,
    'max_day_raw_rows': 0,
    'scope_days': 0,
    'scope_reason': null,
    'prepared_days': 0,
    'todo_days': 0,
    'done_days': 0,
    'skipped_days': 0,
    // List, not a single day — several days can be in flight concurrently
    // (see run()'s bounded worker pool).
    'active_days': <String>[],
    'concurrency': 1,
    'last_error': null,
  };

  Map<String, dynamic> snapshot() => Map<String, dynamic>.from(_diag);

  /// Run a derivation pass. [heavy]=false runs a bounded light pass over the
  /// freshness-critical day: TODAY when raw has reached today, else the latest
  /// pending day. [heavy]=true sweeps every recomputable day.
  /// [force]=true recomputes EVERY non-finalized day regardless of the cursor.
  /// Re-entrant calls are coalesced. Returns the number of days computed.
  Future<int> run(
    Profile profile, {
    bool heavy = false,
    bool force = false,
    void Function(String day, int index, int total)? onDayDone,
  }) async {
    if (_running) return 0;
    if (force) _inputReuse.clear();
    _running = true;
    final stopGen = DeriveStop.generation;
    var cancelled = false;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    _diag
      ..['running'] = true
      ..['stage'] = 'scope'
      ..['mode'] = force ? 'force' : (heavy ? 'heavy' : 'light')
      ..['force'] = force
      ..['started_at'] = startedAt
      ..['finished_at'] = null
      ..['duration_ms'] = null
      ..['raw_pages'] = 0
      ..['raw_rows'] = 0
      ..['max_day_raw_pages'] = 0
      ..['max_day_raw_rows'] = 0
      ..['scope_days'] = 0
      ..['scope_reason'] = null
      ..['prepared_days'] = 0
      ..['todo_days'] = 0
      ..['done_days'] = 0
      ..['skipped_days'] = 0
      ..['active_days'] = <String>[]
      ..['concurrency'] = _deriveConcurrency
      ..['last_error'] = null;

    try {
      final scope = await _deriveScope(heavy: heavy, force: force);
      _diag
        ..['scope_days'] = scope.targetDays.length
        ..['scope_reason'] = scope.reason;
      final dataNowSec = await LocalDb.lastDecodedRecTs() ?? 0;
      if (dataNowSec <= 0) {
        _log('derive: no decoded data');
        return 0;
      }
      final finalized = await LocalDb.finalizedDayIds(kAlgoVersion);
      // A user sleep override (manual / confirmed) must take effect even on a
      // FINALIZED (locked) day — it's the user's word. Force those back into the
      // todo set. (No-raw days are guarded in the per-day loop so we never
      // clobber a good manual result with an empty re-derive once raw is pruned.)
      final overrideDays = {
        ...await LocalDb.sleepOverrideDays(),
        // A nap edit on a finalized day has to take effect too — same reason.
        ...await LocalDb.napEditDays(),
      };
      final todoDays = [
        for (final day in scope.targetDays)
          if (!finalized.contains(day) || overrideDays.contains(day)) day,
      ];
      if (todoDays.isEmpty) {
        _log('derive: all days finalized — nothing to do');
        await _pruneOldDecoded(scope.rawDays, dataNowSec);
        return 0;
      }
      _diag['todo_days'] = todoDays.length;
      _diag['stage'] = 'history';
      final history = await _BaselineHistoryCache.load();
      _log(
        'derive: ${todoDays.length} day(s) '
        '(${force
            ? "force"
            : heavy
            ? "heavy"
            : "light"}; '
        '${scope.reason}; v$kAlgoVersion; '
        'concurrency=$_deriveConcurrency)',
      );

      // Newest-first: `scope.targetDays` sorts ascending (oldest first), which
      // is exactly backwards from what the user actually wants when they open
      // the app after a backlog — today/most-recent should be among the very
      // FIRST days dispatched, not the last one a long sweep gets to. A no-op
      // for the light path (0-1 days), so always safe to apply.
      final orderedDays = todoDays.reversed.toList();

      var done = 0;
      var completed = 0;
      var failures = 0;
      final activeDays = <String>{};
      _diag['stage'] = 'per_day';
      _diag['active_days'] = const <String>[];

      // One day's full prepare→compute→persist body (identical to the old
      // sequential loop's per-iteration work) — extracted so it can run as a
      // unit inside the worker pool below. Concurrency-safe: everything it
      // touches is either (a) day_id-keyed DB rows (independent across days),
      // (b) the read-only `history` snapshot (frozen before this loop starts,
      // refreshed only after it ends — see `_BaselineHistoryCache`), or (c)
      // shared counters mutated via single, non-`await`-split statements,
      // which Dart's cooperative single-threaded scheduler makes atomic
      // relative to the other concurrent workers even though the actual
      // isolate CPU work they await genuinely runs in parallel across cores.
      Future<void> processDay(String dayId) async {
        // A stop leaves the remaining days queued, not failed.
        if (cancelled || DeriveStop.generation != stopGen) {
          cancelled = true;
          return;
        }
        activeDays.add(dayId);
        _diag['active_days'] = activeDays.toList();
        try {
          final prepared = await _prepareTargetDay(dayId);
          // Override day whose raw has been pruned (≥14 d): re-deriving would
          // produce an empty/absent result and clobber the user's manual sleep.
          // Keep the existing locked result instead.
          if (prepared != null &&
              prepared.daySub.isEmpty &&
              overrideDays.contains(dayId)) {
            _log('derive day $dayId skipped: override day, raw pruned — kept');
          } else if (prepared != null) {
            _diag['prepared_days'] = (_diag['prepared_days'] as int) + 1;
            await _derivePreparedDay(
              prepared,
              profile,
              dataNowSec,
              history,
              stopGeneration: stopGen,
            );
            done++;
            _diag['done_days'] = done;
          } else {
            _log('derive day $dayId skipped: no bounded window payload');
            await _markDaySkipped(
              dayId,
              _localNextDayLabelToSec(dayId),
              dataNowSec,
              reason: 'no_bounded_window_payload',
            );
            _diag['skipped_days'] = (_diag['skipped_days'] as int) + 1;
            _diag['last_error'] = 'no_bounded_window_payload day=$dayId';
            failures++;
          }
        } catch (e) {
          if (e is DeriveCancelled || DeriveStop.generation != stopGen) {
            // Stopped mid-day: nothing for this day was committed by the
            // killed isolate, and it is not a failure to mark.
            cancelled = true;
            activeDays.remove(dayId);
            _diag['active_days'] = activeDays.toList();
            return;
          }
          _log('derive day $dayId FAILED/skipped: $e');
          final dayEndSec = _localNextDayLabelToSec(dayId);
          await _markDaySkipped(
            dayId,
            dayEndSec,
            dataNowSec,
            reason: _skipReasonForError(e),
          );
          _diag['skipped_days'] = (_diag['skipped_days'] as int) + 1;
          _diag['last_error'] = '$e';
          failures++;
        }
        activeDays.remove(dayId);
        _diag['active_days'] = activeDays.toList();
        completed++;
        onDayDone?.call(dayId, completed, orderedDays.length);
      }

      await runWithConcurrency(orderedDays, _deriveConcurrency, processDay);
      if (cancelled) throw DeriveStop.error;

      // 4. Cross-day rollup + notifications (best-effort).
      if (done > 0) {
        DeriveStop.check(stopGen);
        _diag['stage'] = 'baselines';
        await _refreshBaselines();
        DeriveStop.check(stopGen);
        _diag['stage'] = 'cross_day';
        await _runCrossDay(profile);
        DeriveStop.check(stopGen);
        _diag['stage'] = 'notifications';
        await _runNotifications();
      }
      // Pruning only after a pass that ran to the end (invariant 9).
      DeriveStop.check(stopGen);
      // 5. Prune raw — never for a day still inside its raw window / un-derived.
      // Runs on EVERY derive, not just a full restage: `rawRetentionDays` is
      // the only cap on the 1 Hz substrate, and behind `scope.fullHistory` it
      // fired only on a manual "Re-analyze data", so an ordinary install grew
      // ~12 MB/day without bound. `_pruneOldDecoded` is day-scoped and bounded,
      // so it is safe to run this often.
      _diag['stage'] = 'prune';
      await _pruneOldDecoded(scope.rawDays, dataNowSec);
      // The timezone hold is a FULL-RESTAGE concept — only a restage actually
      // re-derives every held day — so clearing it stays behind fullHistory.
      if (scope.fullHistory) {
        // Re-baseline the travel guard — but ONLY if every targeted day
        // actually got re-derived under the current timezone. processDay
        // swallows per-day errors and marks the day skipped, so a restage can
        // "finish" with days still unresolved; clearing the hold then would
        // drop it without the adjacency ever having been fixed. (A day kept
        // deliberately — a pruned override day — is not a failure.)
        if (failures == 0) {
          await LocalDb.putBaseline(
            'tz_travel_guard',
            jsonEncode({'offset_min': DateTime.now().timeZoneOffset.inMinutes}),
          );
        } else {
          _log(
            'derive: $failures day(s) unresolved — keeping the timezone hold',
          );
        }
      }
      return done;
    } on DeriveCancelled catch (e) {
      cancelled = true;
      _diag['last_error'] = '$e';
      _log('derive stopped: $e — remaining work stays queued');
      rethrow;
    } catch (e, st) {
      if (DeriveStop.generation != stopGen) {
        cancelled = true;
        _log('derive stopped mid-step: $e — remaining work stays queued');
        throw DeriveStop.error;
      }
      _diag['last_error'] = '$e';
      _log('derive ERROR: $e\n$st');
      return 0;
    } finally {
      // Storage housekeeping runs here, after everything, still holding
      // `_running`. See _runStorageHousekeeping — this is the only place every
      // entry path and every early return actually reaches. A stopped pass
      // skips it and the strain rescale: both wait for a pass that finishes.
      _diag['stage'] = 'housekeeping';
      if (!cancelled) await _runStorageHousekeeping();
      // ONE-SHOT: rescale stored strain onto the recalibrated scale. Days
      // inside the raw window re-derive from substrate above; everything older
      // has none, so its headline is rebuilt from the stored TRIMP + wake
      // window instead. No-ops after the first successful pass
      // (`compute_freshness`), and never fatal — a failed rescale must not take
      // the derive cycle down with it.
      //
      // AFTER the sweep, not before it. It used to be the first statement of
      // run(), so the one launch where it actually fires — the first after the
      // version bump, the launch the user is watching — spent a DB round trip
      // and a bundle decode+encode PER DAY OF HISTORY before today's data was
      // touched at all. Nothing in the sweep reads what it rewrites (it only
      // ever touches days older than `rawRetentionDays`, which no pass
      // re-derives), so the only thing the old ordering bought was that the
      // FIRST cross-day rollup after the bump saw the rescaled history rather
      // than the next one. Still holds `_running`, so nothing else can be
      // reading day_result while it rewrites.
      _diag['stage'] = 'strain_rescale';
      try {
        if (cancelled) throw DeriveStop.error;
        final rescaled = await backfillStrainScale(
          female: workoutSex(profile.sex) == 'female',
        );
        if (rescaled.didWork) {
          _log(
            '[derive] strain rescale: ${rescaled.bundleDays} day(s) '
            'rebuilt, ${rescaled.skipped} skipped (no TRIMP or no wake '
            'window)',
          );
        }
      } catch (e) {
        _log('[derive] strain rescale failed (kept old values): $e');
      }
      _running = false;
      final finishedAt = DateTime.now().millisecondsSinceEpoch;
      _diag
        ..['running'] = false
        ..['stage'] = 'idle'
        ..['active_days'] = const <String>[]
        ..['finished_at'] = finishedAt
        ..['duration_ms'] = finishedAt - startedAt;
    }
  }

  Future<int> runDays(
    Profile profile,
    Set<String> days, {
    bool force = true,
    void Function(String day, int index, int total)? onDayDone,
  }) async {
    if (days.isEmpty) return 0;
    if (_running) return 0;
    if (force) _inputReuse.clear();
    _running = true;
    final stopGen = DeriveStop.generation;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    _diag
      ..['running'] = true
      ..['stage'] = 'scope'
      ..['mode'] = 'selected'
      ..['force'] = force
      ..['started_at'] = startedAt
      ..['finished_at'] = null
      ..['duration_ms'] = null
      ..['raw_pages'] = 0
      ..['raw_rows'] = 0
      ..['max_day_raw_pages'] = 0
      ..['max_day_raw_rows'] = 0
      ..['scope_days'] = days.length
      ..['scope_reason'] = 'selected-days'
      ..['prepared_days'] = 0
      ..['todo_days'] = 0
      ..['done_days'] = 0
      ..['skipped_days'] = 0
      ..['active_days'] = <String>[]
      ..['concurrency'] = _deriveConcurrency
      ..['last_error'] = null;
    try {
      final scope = _scopeForDays(days.toList(), reason: 'selected-days');
      final dataNowSec = await LocalDb.lastDecodedRecTs() ?? 0;
      if (dataNowSec <= 0) {
        _log('derive selected: no decoded data');
        return 0;
      }
      final finalized = await LocalDb.finalizedDayIds(kAlgoVersion);
      final todoDays = [
        for (final day in scope.targetDays)
          if (force || !finalized.contains(day)) day,
      ];
      if (todoDays.isEmpty) {
        _log('derive selected: all days finalized — nothing to do');
        return 0;
      }
      _diag['todo_days'] = todoDays.length;
      final history = await _BaselineHistoryCache.load();
      // Same bounded worker-pool pattern as run() — see its doc for why this
      // is safe (independent day_id-keyed writes + a frozen baseline shared
      // read-only across the whole batch).
      final orderedDays = todoDays.reversed.toList();
      var done = 0;
      var completed = 0;
      var failures = 0;
      final activeDays = <String>{};

      Future<void> processDay(String dayId) async {
        DeriveStop.check(stopGen);
        activeDays.add(dayId);
        _diag['active_days'] = activeDays.toList();
        try {
          final prepared = await _prepareTargetDay(dayId);
          if (prepared != null) {
            _diag['prepared_days'] = (_diag['prepared_days'] as int) + 1;
            await _derivePreparedDay(
              prepared,
              profile,
              dataNowSec,
              history,
              stopGeneration: stopGen,
            );
            done++;
            _diag['done_days'] = done;
          } else {
            _diag['skipped_days'] = (_diag['skipped_days'] as int) + 1;
            _diag['last_error'] = 'no_bounded_window_payload day=$dayId';
            failures++;
          }
        } catch (e) {
          if (e is DeriveCancelled || DeriveStop.generation != stopGen) rethrow;
          _log('derive selected day $dayId FAILED/skipped: $e');
          _diag['skipped_days'] = (_diag['skipped_days'] as int) + 1;
          _diag['last_error'] = '$e';
          failures++;
        }
        activeDays.remove(dayId);
        _diag['active_days'] = activeDays.toList();
        completed++;
        onDayDone?.call(dayId, completed, orderedDays.length);
      }

      await runWithConcurrency(orderedDays, _deriveConcurrency, processDay);
      DeriveStop.check(stopGen);
      // A SELECTED re-analyze that happens to cover the whole raw history, with
      // every day resolved, is a full restage by any other name — it re-derived
      // every day under the current timezone, so it clears the travel hold too.
      // A partial selection deliberately does not: those days say nothing about
      // the ones still held.
      if (force && failures == 0) {
        final rawDays = (await LocalDb.decodedRecTsMaxByDay()).keys.toSet();
        if (rawDays.isNotEmpty && rawDays.difference(days).isEmpty) {
          await LocalDb.putBaseline(
            'tz_travel_guard',
            jsonEncode({'offset_min': DateTime.now().timeZoneOffset.inMinutes}),
          );
          _log(
            'derive selected: full-coverage restage — timezone hold cleared',
          );
        }
      }
      if (done > 0) {
        await _refreshBaselines();
        DeriveStop.check(stopGen);
        await _runCrossDay(profile);
        DeriveStop.check(stopGen);
        await _runNotifications();
      }
      return done;
    } catch (e, st) {
      if (e is DeriveCancelled || DeriveStop.generation != stopGen) {
        _diag['last_error'] = '${DeriveStop.error}';
        throw DeriveStop.error;
      }
      _log('derive selected ERROR: $e\n$st');
      return 0;
    } finally {
      if (DeriveStop.generation == stopGen) await _runStorageHousekeeping();
      final finishedAt = DateTime.now().millisecondsSinceEpoch;
      _diag
        ..['running'] = false
        ..['stage'] = 'idle'
        ..['active_days'] = const <String>[]
        ..['finished_at'] = finishedAt
        ..['duration_ms'] = finishedAt - startedAt;
      _running = false;
    }
  }

  static const int _rawDecodeBatchSize = 2000;
  static const int _maxDayRawRows = 500000;
  static const int _maxDayRawPages = 300;

  Future<PreparedDerivationDay?> _prepareTargetDay(String dayId) async {
    // Per-day page/row totals used to live in the shared `_diag` map (reset
    // then accumulated across this day's 2-3 substrate loads). Under
    // concurrent per-day processing (see `run()`), multiple days resetting/
    // incrementing the SAME shared fields would race and produce garbage
    // diagnostics (never a correctness issue for the derived VALUES — this
    // is telemetry-only). Each day now gets its own local accumulator,
    // merged into the shared running max exactly once, below.
    final stats = _PrepareStats();
    final candidate = await _sleepCandidateForDay(dayId, stats: stats);
    final dayStart = _localDayLabelToSec(dayId);
    final dayEnd = _localNextDayLabelToSec(dayId);
    // Load the day PLUS the nap boundary buffer in ONE pass (each
    // _loadSubstrateRange spawns its own isolate, so a second load would
    // double that cost) and slice the calendar day back out of it. Without
    // this, the live decoded path — run()/runDays()/rescanRecent(), i.e. every
    // non-import day — fell back to napSub == daySub and went on bisecting
    // naps at midnight.
    final napSub = await _loadSubstrateRange(
      dayStart,
      dayEnd - 1 + napBoundaryBufferSec,
      dayId: dayId,
      stats: stats,
    );
    final daySub = napSub.slice(dayStart, dayEnd);
    Substrate sleepSub = Substrate.empty;
    if (candidate.present &&
        candidate.sleepOffsetSec > candidate.sleepOnsetSec) {
      sleepSub = await _loadSubstrateRange(
        candidate.sleepOnsetSec,
        candidate.sleepOffsetSec - 1,
        dayId: dayId,
        stats: stats,
      );
    }
    // Single safe merge into the shared max-tracking diagnostics — one
    // statement, no `await` in between, so it's atomic relative to any other
    // concurrently-running day's identical merge.
    if (stats.pages > (_diag['max_day_raw_pages'] as int)) {
      _diag['max_day_raw_pages'] = stats.pages;
    }
    if (stats.rows > (_diag['max_day_raw_rows'] as int)) {
      _diag['max_day_raw_rows'] = stats.rows;
    }
    return candidate.toPreparedDay(
      daySub: daySub,
      napSub: napSub,
      sleepSub: sleepSub,
    );
  }

  Future<SleepSessionCandidate> _sleepCandidateForDay(
    String dayId, {
    _PrepareStats? stats,
  }) async {
    // A user sleep override is the source of truth — never serve the cached auto
    // candidate, and don't cache the override result (so a later edit / clear is
    // not shadowed by a stale artifact). The auto path keeps its finalized cache.
    final overrideRow = await LocalDb.getSleepOverride(dayId);
    final override = overrideRow == null
        ? null
        : SleepWindowOverride(
            dayId: dayId,
            onsetSec: (overrideRow['onset_ts'] as num).toInt(),
            offsetSec: (overrideRow['offset_ts'] as num).toInt(),
            source: overrideRow['source'] as String? ?? 'manual',
          );

    if (override == null) {
      final finalized = await LocalDb.finalizedDayIds(kAlgoVersion);
      if (finalized.contains(dayId)) {
        final cached = await LocalDb.sleepSessionCandidate(dayId, kAlgoVersion);
        final raw = cached?['payload_json'];
        if (raw is String && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              return SleepSessionCandidate.fromJson(
                decoded.cast<String, dynamic>(),
              );
            }
          } catch (_) {
            // Fall through to rebuild the artifact.
          }
        }
      }
    }
    final range = _targetDayWindow(dayId);
    final searchSub = await _loadSubstrateRange(
      range.$1,
      range.$2,
      dayId: dayId,
      stats: stats,
    );
    // PERSONALIZED STAGER (v42): stage on a WORKER isolate, NOT the main/UI
    // thread. cardioStager reads analytics "ambient" globals — the rolling sleep
    // profile (`cardioUserProfile`) it blends in (bounded ≤0.5) and the
    // observation-recording flag it folds back afterwards. Those globals are
    // ISOLATE-LOCAL (they don't cross `Isolate.run`), which is why v42 originally
    // ran staging on the main isolate — and, per-30-s-epoch over a full night,
    // that landed the trig/Lomb–Scargle load on the UI thread and produced the
    // recurring multi-second freezes → Android ANRs (Crashlytics 0.9.13). We now
    //   (1) read the profile from the DB HERE (the main isolate owns the DB) as
    //       plain JSON,
    //   (2) re-arm the ambient globals and run the staging + EWMA profile fold
    //       INSIDE the worker, and
    //   (3) return the staged candidate + folded profile as plain JSON to persist
    //       back on main.
    // The worker isolate dies after `Isolate.run`, so the recording flag can't
    // leak into the next day's derivation — no try/finally reset needed.
    final profileJson = await _loadSleepUserProfileJson();
    // Which day_ids have ALREADY been folded into that profile. See
    // [_kFoldedDaysKey] for why this exists and why a legacy profile that
    // lacks it is discarded rather than trusted.
    final foldedDays = SleepProfilePolicy.foldedDays(profileJson);
    final mayFold = SleepProfilePolicy.shouldFold(
      alreadyFolded: foldedDays,
      dayId: dayId,
      hasOverride: override != null,
    );
    // The habitual-midsleep prior needs 14 distinct days and this call carries
    // ~36 h of substrate, so without the STORED windows the prior can never
    // fire in production and every night is anchored to the 03:30 cold start.
    // Read on main (the DB lives here) and capture into the worker.
    final priorSleep = await _storedSleepHistory(excludeDay: dayId);
    // Cancellable + TIMED OUT. This site previously used a bare `Isolate.run`
    // with no timeout at all, so a hung staging pass never completed its future
    // — `_running` stayed true and `DeriveScheduler._drain` never returned, i.e.
    // all derivation was dead until app restart.
    final dayContext = DayClock.snapshot();
    final (candidateJson, observationJson) = await _runIsolateCancellable(
      () {
        DayClock.restore(dayContext);
        try {
          final p = profileJson == null
              ? null
              : ana.SleepUserProfile.fromJson(
                  (jsonDecode(profileJson) as Map).cast<String, dynamic>(),
                );
          // Warm-up gate — see SleepProfilePolicy.shouldBlend. Note the profile
          // is only WITHHELD FROM STAGING here; accumulation into it happens on
          // the main isolate in _foldObservationIntoProfile, which re-reads the
          // current profile, so a withheld night still counts toward `nights`.
          ana.cardioUserProfile = SleepProfilePolicy.shouldBlend(p?.nights)
              ? p
              : null;
        } catch (_) {
          // Defense in depth: an incompatible/outdated persisted profile must
          // fall back to a cold start, never throw inside the worker (an uncaught
          // throw here bubbles to processDay's per-day catch → the day gets stuck
          // marked 'error' every pass until the row is fixed).
          ana.cardioUserProfile = null;
        }
        ana.cardioRecordObservations = true;
        ana.resetCardioObservations();
        final candidate = prepareSleepSessionCandidate(
          searchSub,
          targetDay: dayId,
          override: override,
          priorSleep: priorSleep,
        );
        // Fold the MAIN sleep (most epochs) of a freshly-staged night into the
        // rolling profile — done here in the worker because the observations live
        // in THIS isolate's globals. Skipped for overrides. EWMA self-seeds.
        String? observationJson;
        // IDEMPOTENT PER DAY. `fold()` is an EWMA step that also increments
        // `nights`, and this path runs on EVERY staging pass for a day — an
        // algo-version bump, a BLE-drain re-derive, a backfill sweep. Without a
        // guard the same handful of real nights fold hundreds of times: a real
        // user export showed `nights: 1348` against 12 days of data, which pins
        // `personalWeight` at its 0.5 cap from day one and collapses the EWMA
        // onto whichever day was re-derived last. Measured effect of that
        // corrupt profile on the same nights: wake 4.3% -> 36.4%, deep 1.9% ->
        // 0.0%. One fold per day_id, ever.
        if (mayFold) {
          final obs = ana.takeCardioObservations();
          if (obs.isNotEmpty) {
            obs.sort((a, b) => b.epochs.compareTo(a.epochs));
            final main = obs.first;
            if (main.epochs >= 120) {
              // require ≥60 min — not a nap.
              // Return the raw OBSERVATION, not a folded profile. Folding here
              // would bake in the profile this worker read before staging began,
              // and a concurrent day may have written a newer one since. The
              // fold happens on the main isolate under the profile lock.
              observationJson = jsonEncode({
                'epochs': main.epochs,
                'hr_floor_p5': main.hrFloorP5,
                'hr_floor_p25': main.hrFloorP25,
                'hr_sleep_median': main.hrSleepMedian,
                'hr_arousal': main.hrArousal,
                'rmssd_med': main.rmssdMed,
                'rmssd_mad': main.rmssdMad,
                'enmo_still_cut': main.enmoStillCut,
                'enmo_move_cut': main.enmoMoveCut,
                'lfhf_med': main.lfhfMed,
                'rk_med': main.rkMed,
              });
            }
          }
        }
        return (jsonEncode(candidate.toJson()), observationJson);
      },
      _perDayTimeout,
      label: 'sleep-staging $dayId',
    );
    final candidate = SleepSessionCandidate.fromJson(
      (jsonDecode(candidateJson) as Map).cast<String, dynamic>(),
    );
    if (override == null) {
      // NEVER RE-STAGE A NIGHT SHORTER THAN THE ONE ALREADY BANKED (#242).
      //
      // A day re-stages on every pass for its first 48 h, and the substrate it
      // stages over does not only grow: `pruneDecodedBeforeRecTs` runs once the
      // covering day is derived, so a later pass can look at the same night
      // through less data and produce a shorter one — which then REPLACED the
      // good candidate, and the day rebuilt from it. That is the reported "it
      // got fixed, then a few syncs later it went back", and it is a write-path
      // defect, not a staging one (a mid-night wake bridges and sums correctly).
      //
      // The guard belongs HERE rather than on the day result: the candidate is
      // earlier of the sleep block, the hypnogram AND every sleep scalar, so
      // keeping the richer one keeps the whole day internally consistent.
      // Swapping a richer sleep block into a thinner day's bundle would pair
      // last pass's night with this pass's stage minutes.
      //
      // Keyed at this algo version, so a bump still re-stages from scratch —
      // that is what a bump is for. An override never reaches this branch, so a
      // user shortening their own night is untouched.
      final stored = await LocalDb.sleepSessionCandidate(dayId, kAlgoVersion);
      final storedJson = stored?['payload_json'];
      if (storedJson is String && storedJson.isNotEmpty) {
        try {
          final prev = SleepSessionCandidate.fromJson(
            (jsonDecode(storedJson) as Map).cast<String, dynamic>(),
          );
          if (isRicherSleep(prev, candidate)) {
            _log(
              'derive $dayId: kept the banked night '
              '(${_tstSec(prev)} s) over this pass\'s '
              '${_tstSec(candidate)} s — less substrate, not a shorter night',
            );
            return prev;
          }
        } catch (_) {
          // Undecodable stored candidate — the fresh one is strictly better.
        }
      }
      await LocalDb.putSleepSessionCandidate(
        dayId: dayId,
        algoVersion: kAlgoVersion,
        payloadJson: candidateJson,
      );
      if (observationJson != null) {
        // BEST-EFFORT, and deliberately isolated from the day's success path.
        // The fold is bookkeeping; the day's real result is already persisted
        // above. `updateBaseline` takes an exclusive SQLite write lock, and the
        // whole point of this change is that two derivation isolates contend
        // for it — so SQLITE_BUSY here is an EXPECTED outcome, not an
        // exceptional one. Letting it escape would hit processDay's broad
        // catch, which calls `_markDaySkipped` and increments `failures`,
        // throwing away a fully computed day (and holding the timezone) over a
        // bookkeeping write.
        //
        // KNOWN LIMITATION — a swallowed failure here is PERMANENT for this
        // day, not retried. Once the day finalizes, the cached-candidate
        // short-circuit at the top of this method returns before staging runs,
        // so `observationJson` is never regenerated and the fold never happens.
        // Same for a day whose override is later removed if it already has a
        // cached candidate from before the override.
        //
        // Accepted deliberately rather than fixed: the profile is an EWMA with
        // a ~14-night horizon and a hard 0.5 blend cap, so one missing night is
        // a small perturbation, whereas a retry path needs durable pending
        // state and a way to distinguish "failed, retry" from "declined
        // permanently" (a <120-epoch nap never folds, and would otherwise
        // bypass the candidate cache and re-stage on every sweep forever).
        // If the fold ever stops being best-effort, that state machine is the
        // thing to build — do not simply bypass the cache.
        try {
          await _foldObservationIntoProfile(dayId, observationJson);
        } catch (e) {
          _log(
            'sleep profile fold skipped for $dayId (day result kept, '
            'this night will not contribute to the profile): $e',
          );
        }
      }
    }
    return candidate;
  }

  /// Fold one night's observation into the shared profile, serialised against
  /// every other day in the sweep.
  ///
  /// The profile is RE-READ inside the lock and [SleepProfilePolicy.shouldFold]
  /// re-checked, because the value this day read before staging is stale by
  /// definition — a concurrently-derived day may have folded since. Skipping
  /// that re-check is what turns a read-modify-write race into a lost fold plus
  /// a lost day_id, and the day then re-folds forever.
  Future<void> _foldObservationIntoProfile(
    String dayId,
    String observationJson,
  ) async {
    final Map<String, dynamic> o;
    try {
      o = (jsonDecode(observationJson) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    double? d(String k) => (o[k] as num?)?.toDouble();
    final observed = ana.SleepNightObservation(
      epochs: (o['epochs'] as num?)?.toInt() ?? 0,
      hrFloorP5: d('hr_floor_p5'),
      hrFloorP25: d('hr_floor_p25'),
      hrSleepMedian: d('hr_sleep_median'),
      hrArousal: d('hr_arousal'),
      rmssdMed: d('rmssd_med'),
      rmssdMad: d('rmssd_mad'),
      enmoStillCut: d('enmo_still_cut'),
      enmoMoveCut: d('enmo_move_cut'),
      lfhfMed: d('lfhf_med'),
      rkMed: d('rk_med'),
    );
    // The whole read-modify-write happens inside ONE exclusive DB transaction.
    // A Dart mutex cannot do this job: derivation can run from MORE THAN ONE
    // ISOLATE (Android headless sync wakes construct their own DerivationEngine
    // off the main one), and a `static` lock has one copy per isolate — so a
    // background heavy pass and a foreground sweep would each read the same
    // profile, fold, and clobber the other, losing both the fold and its
    // day_id from folded_days. SQLite's write lock is cross-connection and
    // therefore cross-isolate.
    await LocalDb.updateBaseline('sleep_user_profile', (current) {
      // Re-derive freshness INSIDE the transaction: the value this day read
      // before staging is stale by definition, another lane may have folded
      // since. Returning null leaves the row untouched.
      final usable = SleepProfilePolicy.usableProfileJson(current);
      final freshDays = SleepProfilePolicy.foldedDays(usable);
      if (!SleepProfilePolicy.shouldFold(
        alreadyFolded: freshDays,
        dayId: dayId,
        hasOverride: false,
      )) {
        return null;
      }
      final ana.SleepUserProfile base;
      try {
        base = usable == null
            ? const ana.SleepUserProfile()
            : ana.SleepUserProfile.fromJson(
                (jsonDecode(usable) as Map).cast<String, dynamic>(),
              );
      } catch (_) {
        return null; // unreadable — leave it for the cold-start path
      }
      return jsonEncode(
        SleepProfilePolicy.withFoldedDays(
          base.fold(observed).toJson(),
          freshDays,
          dayId,
        ),
      );
    });
  }

  /// Read the persisted per-user sleep profile (`baselines` key
  /// `sleep_user_profile`) as raw JSON, for passing into the staging worker
  /// isolate. Absent/corrupt ⇒ null (cold start). DB read stays on the main
  /// isolate (the DB owner); the worker reconstructs the profile from this JSON.
  ///
  /// A profile written before per-day fold tracking existed carries no
  /// [_kFoldedDaysKey] and therefore an untrustworthy `nights` count and an
  /// EWMA skewed by repeated re-folds of the same nights. We cannot repair it
  /// (there is no record of which days went in), so we DISCARD it and rebuild.
  /// That degrades to pure per-night-local baselines — the cold-start path
  /// cardio_stager.dart was validated on — and the profile re-earns its weight
  /// over the next few nights under the corrected accounting.
  Future<String?> _loadSleepUserProfileJson() async {
    final row = await LocalDb.baseline('sleep_user_profile');
    final raw = row?['payload_json'];
    if (raw is! String || raw.isEmpty) return null;
    // Validate here (mirrors the cached-candidate guard above) so a corrupt
    // payload becomes a cold start, per this method's contract — rather than
    // throwing later inside the staging worker's `jsonDecode(...) as Map`.
    return SleepProfilePolicy.usableProfileJson(raw);
  }

  /// Stored sleep windows for the trailing [days] days, as the history the
  /// habitual-midsleep prior takes ([calendarDays]'s `priorSleep`).
  ///
  /// `window_json` is a projected column, so this is one small query — no
  /// bundle decode. Days with no window contribute nothing; the prior itself
  /// abstains below 14 distinct days.
  ///
  /// [excludeDay] drops the day being staged: its stored window is the PREVIOUS
  /// derive's answer for the very question being asked, and a re-derive that
  /// reads its own last answer back is not reproducible.
  Future<List<({int startSec, int endSec, String dayKey})>>
  _storedSleepHistory({int days = 60, String? excludeDay}) async {
    final out = <({int startSec, int endSec, String dayKey})>[];
    try {
      for (final r in await LocalDb.sleepWindowRows(days)) {
        final dayKey = r['day_id'] as String?;
        if (dayKey == null || dayKey.isEmpty || dayKey == excludeDay) continue;
        final raw = r['window_json'];
        if (raw is! String || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        // `value` is the string '—' on a night with no sleep — only a Map when
        // a window was actually found.
        final v = decoded is Map ? decoded['value'] : null;
        if (v is! Map) continue;
        final onsetMs = (v['onset_ms'] as num?)?.toDouble();
        final offsetMs = (v['offset_ms'] as num?)?.toDouble();
        if (onsetMs == null || offsetMs == null) continue;
        final startSec = (onsetMs / 1000).round();
        final endSec = (offsetMs / 1000).round();
        if (startSec <= 0 || endSec <= startSec) continue;
        out.add((startSec: startSec, endSec: endSec, dayKey: dayKey));
      }
    } catch (e) {
      _log('sleep history for midsleep prior FAILED/skipped: $e');
    }
    return out;
  }

  Future<Substrate> _loadSubstrateRange(
    int fromRecTs,
    int toRecTs, {
    required String dayId,
    _PrepareStats? stats,
  }) async {
    if (toRecTs < fromRecTs) return Substrate.empty;
    final port = ReceivePort();
    // onError/onExit are LOAD-BEARING. Without them, an uncaught throw inside
    // the worker (a malformed SQLite row reaching one of the numeric reads in
    // its 'page' handler — the worker only ever reported errors from its
    // 'finish' branch) killed the isolate silently, and this side awaited
    // `result.future` FOREVER with `_running == true`: DeriveScheduler._drain
    // never returned and ALL derivation was dead until app restart. Now a
    // worker death fails the future, and the timeout below bounds the wait
    // even if no signal arrives at all.
    final isolate = await Isolate.spawn(
      derivationPrepareWorker,
      port.sendPort,
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final ready = Completer<SendPort>();
    final result = Completer<Substrate>();
    // A failure completes BOTH completers, but we may bail out via `ready` and
    // never await `result` — register a listener so that error is never an
    // unobserved async error. (The real error still propagates via `ready`.)
    unawaited(result.future.catchError((_) => Substrate.empty));
    late final StreamSubscription<dynamic> sub;
    void fail(Object error) {
      if (!ready.isCompleted) ready.completeError(error);
      if (!result.isCompleted) result.completeError(error);
    }

    sub = port.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is Map && message['type'] == 'result') {
        final kind = message['kind']?.toString();
        if (kind == 'substrate') {
          final payload = ((message['payload'] as Map?) ?? const {})
              .cast<String, dynamic>();
          if (!result.isCompleted) result.complete(Substrate.fromJson(payload));
        }
        return;
      }
      if (message is Map && message['type'] == 'error') {
        fail(Exception('prepare worker error: ${message['error']}'));
        return;
      }
      if (message is List) {
        // `onError` wire format ([error, stackTrace]) — an uncaught throw.
        fail(
          Exception(
            'prepare worker crashed: '
            '${message.isNotEmpty ? message.first : "no detail"}',
          ),
        );
        return;
      }
      if (message == null) {
        // `onExit` — the isolate ended without ever sending a result.
        fail(StateError('prepare worker exited without a result'));
      }
    });
    try {
      final worker = await ready.future;
      worker.send(const {'type': 'config', 'mode': 'substrate'});
      int? afterRecTs;
      int? afterCursor;
      var rangePages = 0;
      var rangeRows = 0;
      // Low water mark for the BEAT read, which is NOT the same window as the
      // frame read. Paging is driven by `decoded_onehz`, but a beat can exist
      // for a second with no 1 Hz row at all (gen4 R10-lite is hr-only and
      // stays out of that table — see db.dart `_queueDecodedOneHz`). Clamping
      // each page's beat read to that page's own first/last frame second
      // dropped every such beat that fell before the day's first frame, after
      // its last, or in the seam between two pages. Each page instead reads
      // beats from wherever the previous page stopped, and the tail is swept
      // after the loop — so the day's beat window is covered exactly once.
      var rrFrom = fromRecTs;
      while (true) {
        final decodedRows = await LocalDb.decodedOneHzBatchByRecTsRange(
          limit: _rawDecodeBatchSize,
          fromRecTs: fromRecTs,
          toRecTs: toRecTs,
          afterRecTs: afterRecTs,
          afterCounter: afterCursor,
        );
        if (decodedRows.isNotEmpty) {
          _trackPrepareBatch(decodedRows.length);
          rangePages += 1;
          rangeRows += decodedRows.length;
          if (stats != null) {
            stats.pages += 1;
            stats.rows += decodedRows.length;
          }
          _enforcePrepareBudget(
            dayId: dayId,
            fromRecTs: fromRecTs,
            toRecTs: toRecTs,
            rangePages: rangePages,
            rangeRows: rangeRows,
          );
          // The page is ordered rec_ts ASC, so last = max second. decoded_rr
          // shares the rec_ts key, so [rrFrom, lastRecTs] is a PK range read —
          // no counter span (which broke across the strap's reboot reset).
          final lastRecTs = (decodedRows.last['rec_ts'] as num?)?.toInt();
          final rrRows = lastRecTs == null
              ? const <Map<String, dynamic>>[]
              : await LocalDb.decodedRrByRecTsRange(
                  fromRecTs: rrFrom,
                  toRecTs: lastRecTs,
                );
          if (lastRecTs != null) rrFrom = lastRecTs + 1;
          worker.send({'type': 'page', 'frames': decodedRows, 'rr': rrRows});
          final last = decodedRows.last;
          afterRecTs = (last['rec_ts'] as num?)?.toInt() ?? afterRecTs;
          afterCursor = (last['counter'] as num?)?.toInt() ?? afterCursor;
          if (decodedRows.length < _rawDecodeBatchSize) break;
          continue;
        }
        break;
      }
      // The tail: beats after the last frame second (or, on a range with no
      // frames at all, the whole range). Usually zero rows and one indexed
      // lookup; when it is not, these are seconds the band recorded and only
      // reported beats for.
      if (rrFrom <= toRecTs) {
        final tailRr = await LocalDb.decodedRrByRecTsRange(
          fromRecTs: rrFrom,
          toRecTs: toRecTs,
        );
        if (tailRr.isNotEmpty) {
          worker.send({
            'type': 'page',
            'frames': const <Map<String, dynamic>>[],
            'rr': tailRr,
          });
        }
      }
      worker.send(const {'type': 'finish'});
      // BOUNDED. `result.future` had no timeout at all, so any path that left
      // the worker unable to answer hung this call — and with it the whole
      // engine — permanently.
      return await result.future.timeout(
        _perDayTimeout,
        onTimeout: () => throw TimeoutException(
          'substrate prepare for $dayId timed out after $_perDayTimeout',
        ),
      );
    } finally {
      // ALWAYS tear down: on success, on error, and on timeout. The isolate is
      // killed rather than abandoned so a wedged worker can never outlive the
      // call that spawned it.
      await sub.cancel();
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }

  // Cumulative across the WHOLE run — safe under concurrent per-day
  // processing since each field is a simple, non-`await`-split increment
  // (order across days doesn't matter for a total). Per-day max tracking
  // moved to `_PrepareStats` + the single merge at the end of
  // `_prepareTargetDay`, since that DOES need per-day isolation.
  void _trackPrepareBatch(int rows) {
    _diag['raw_pages'] = (_diag['raw_pages'] as int) + 1;
    _diag['raw_rows'] = (_diag['raw_rows'] as int) + rows;
  }

  void _enforcePrepareBudget({
    required String dayId,
    required int fromRecTs,
    required int toRecTs,
    required int rangePages,
    required int rangeRows,
  }) {
    if (rangeRows > _maxDayRawRows || rangePages > _maxDayRawPages) {
      throw Exception(
        'day_prepare_budget_exceeded day=$dayId rows=$rangeRows '
        'pages=$rangePages range=$fromRecTs-$toRecTs',
      );
    }
  }

  Future<_DeriveScope> _deriveScope({
    required bool heavy,
    required bool force,
  }) async {
    final rawByDay = await LocalDb.decodedRecTsMaxByDay();
    if (rawByDay.isEmpty) {
      return const _DeriveScope(
        fullHistory: true,
        targetDays: [],
        reason: 'empty',
      );
    }
    final rawDays = rawByDay.keys.toList()..sort();
    if (force) {
      // A full restage resolves any held-back timezone-adjacent days on its
      // own, so it clears the guard — but only once it has actually RUN. See
      // the reset at the end of run(): clearing it here, at scope-selection
      // time, meant an interrupted restage still dropped the hold.
      return _scopeForDays(
        rawDays,
        reason: 'full-history',
        fullHistory: true,
        rawDays: rawDays,
      );
    }

    final finalized = await LocalDb.finalizedDayIds(kAlgoVersion);
    var pending = [
      for (final day in rawDays)
        if (!finalized.contains(day)) day,
    ];

    // decodedRecTsMaxByDay() buckets by the CURRENT device timezone, but
    // `finalized` was frozen under whatever timezone was active when each day
    // was derived. A real cross-timezone trip (not an ~1h DST shift) can make
    // the SAME rec_ts rows relabel to a day adjacent to one already finalized
    // — looking like a brand-new "pending" night that's really a duplicate, or
    // silently landing on an already-finalized day_id and looking lost. Once
    // that's detected, hold off auto-deriving anything adjacent to finalized
    // data until "Re-analyze data" (full restage) resolves it properly.
    if (await _timezoneTravelSuspected()) {
      final adjacent = <String>{
        for (final day in finalized) ..._adjacentDayIds(day),
      };
      final held = pending.where(adjacent.contains).toList();
      if (held.isNotEmpty) {
        _log(
          'derive: possible timezone change — holding ${held.length} day(s) '
          'adjacent to finalized data until Re-analyze data runs: $held',
        );
        pending = pending.where((d) => !adjacent.contains(d)).toList();
        if (pending.isEmpty) {
          // Everything pending was held. Falling through to the
          // 'latest-finalized-check' below would re-derive rawDays.last —
          // one of the very days just held — defeating the hold entirely.
          return _DeriveScope(
            fullHistory: false,
            targetDays: const [],
            reason: 'tz-travel-hold',
            rawDays: rawDays,
          );
        }
      }
    }
    if (pending.isEmpty) {
      return _scopeForDays(
        [rawDays.last],
        reason: 'latest-finalized-check',
        rawDays: rawDays,
      );
    }

    if (heavy) {
      return _scopeForDays(pending, reason: 'pending-span', rawDays: rawDays);
    }

    final light = selectLightDeriveDays(
      rawDays: rawByDay.keys.toSet(),
      pendingDays: pending,
      today: LocalDb.localDayLabelNow(),
    );
    return _scopeForDays(light.days, reason: light.reason, rawDays: rawDays);
  }

  /// The day before and after [dayId] ('YYYY-MM-DD'), DST-safe (goes through
  /// real DateTime arithmetic, not a raw ±86400s offset).
  static List<String> _adjacentDayIds(String dayId) {
    final d = DateTime.tryParse(dayId);
    if (d == null) return const [];
    return [
      dayLabelOf(DateTime(d.year, d.month, d.day - 1)),
      dayLabelOf(DateTime(d.year, d.month, d.day + 1)),
    ];
  }

  /// True right after the device timezone jumps by more than a real DST shift
  /// ever would (>=3h) — a strong signal of actual cross-timezone travel
  /// rather than a seasonal clock change. Stays true across repeated calls
  /// (derive runs many times a day) by only ever updating the persisted
  /// baseline offset when NO jump is detected — updating it unconditionally
  /// would make the very next call see lastOffset == nowOffset and silently
  /// drop the guard after a single pass. `force` (full restage) is what
  /// resets it, per _deriveScope.
  static const int _tzJumpThresholdMin = 180;
  Future<bool> _timezoneTravelSuspected() async {
    // Persisted boundaries replace the former hold-on-travel workaround.
    if (DayClock.days.isNotEmpty) return false;
    final nowOffsetMin = DateTime.now().timeZoneOffset.inMinutes;
    final row = await LocalDb.baseline('tz_travel_guard');
    final raw = row?['payload_json'];
    int? lastOffsetMin;
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) lastOffsetMin = (d['offset_min'] as num?)?.toInt();
      } catch (_) {
        // fall through — treat as unknown
      }
    }
    if (lastOffsetMin == null) {
      await LocalDb.putBaseline(
        'tz_travel_guard',
        jsonEncode({'offset_min': nowOffsetMin}),
      );
      return false;
    }
    final jumped = (nowOffsetMin - lastOffsetMin).abs() >= _tzJumpThresholdMin;
    if (!jumped) {
      await LocalDb.putBaseline(
        'tz_travel_guard',
        jsonEncode({'offset_min': nowOffsetMin}),
      );
    }
    return jumped;
  }

  _DeriveScope _scopeForDays(
    List<String> days, {
    required String reason,
    bool fullHistory = false,
    List<String> rawDays = const [],
  }) {
    final sorted = days.toSet().toList()..sort();
    if (sorted.isEmpty || fullHistory) {
      return _DeriveScope(
        fullHistory: true,
        targetDays: sorted,
        reason: reason,
        rawDays: rawDays,
      );
    }
    return _DeriveScope(
      fullHistory: false,
      targetDays: sorted,
      reason: reason,
      rawDays: rawDays,
    );
  }

  // ── baseline-dirty recent rescan ─────────────────────────────────────────────

  /// Re-derive the recent (≤ raw-retention) window — INCLUDING finalized days —
  /// when the rolling baseline has actually shifted, so baseline-DEPENDENT
  /// scalars (readiness/recovery, illness/anomaly, stress) on already-finalized
  /// days refresh as later data moves their baseline.
  ///
  /// CHEAP BY DEFAULT: we gate on a baseline SIGNATURE — a stable hash of the
  /// current rolling baseline compared to the stored `baseline_sig` cursor. If unchanged
  /// we do ~one read and return 0 (no redundant writes). Only a real baseline
  /// change re-derives, and only the recent window (older raw is already pruned).
  ///
  /// Re-entrant calls are coalesced (shares the `_running` guard with run()).
  /// Best-effort: returns the number of days re-derived (0 on skip/empty/error).
  Future<int> rescanRecent(
    Profile profile, {
    void Function(String day, int index, int total)? onDayDone,
  }) async {
    if (_running) return 0;
    _running = true;
    final stopGen = DeriveStop.generation;
    try {
      // Baseline gate: compute the CURRENT signature and compare to the stored
      // one. Unchanged → nothing to refresh; bail cheaply (no redundant writes).
      final sig = await _baselineSignature();
      final prev = await LocalDb.getCursor('baseline_sig');
      if (sig == prev) {
        _log('baseline unchanged — rescan skipped');
        return 0;
      }

      // Same hold `_deriveScope` installs, for the same reason. This re-derives
      // FINALIZED days by design, and `decodedRecTsMaxByDay` buckets them in
      // the CURRENT timezone — so after a real trip it relabels and overwrites
      // (ConflictAlgorithm.replace) exactly the nights the hold was protecting,
      // minutes after `run()` logged that it was protecting them. Wait for
      // "Re-analyze data", which is what clears the guard.
      //
      // Deliberately BEFORE the `baseline_sig` cursor is stored: the baseline
      // change is still pending, so the rescan runs once the hold lifts.
      if (await _timezoneTravelSuspected()) {
        _log(
          'rescan: possible timezone change — held until Re-analyze data runs',
        );
        return 0;
      }

      final rawByDay = await LocalDb.decodedRecTsMaxByDay();
      if (rawByDay.isEmpty) {
        _log('rescan: no decoded data');
        return 0;
      }
      final dataNowSec = await LocalDb.lastDecodedRecTs() ?? 0;
      if (dataNowSec <= 0) {
        _log('rescan: no data edge');
        return 0;
      }
      final cutoffSec = dataNowSec - _rescanWindowDays * 86400;
      final todoDays = [
        for (final dayId in rawByDay.keys)
          if (_localNextDayLabelToSec(dayId) >= cutoffSec) dayId,
      ]..sort();
      if (todoDays.isEmpty) {
        _log('rescan: no recent decoded-backed days');
        await LocalDb.setCursor('baseline_sig', sig);
        return 0;
      }
      _log(
        'rescan: baseline changed — re-deriving ${todoDays.length} '
        'recent day(s) (incl. finalized; v$kAlgoVersion)',
      );

      final history = await _BaselineHistoryCache.load();
      // Same bounded worker-pool pattern as run()/runDays — up to
      // _rescanWindowDays (21) days is exactly the kind of sweep that used
      // to run fully sequentially for no reason (independent day_id-keyed
      // writes + one frozen baseline snapshot shared read-only here).
      final orderedDays = todoDays.reversed.toList();
      var done = 0;
      var completed = 0;
      var failures = 0;

      Future<void> processDay(String dayId) async {
        if (DeriveStop.generation != stopGen) return;
        try {
          final prepared = await _prepareTargetDay(dayId);
          if (prepared != null) {
            await _derivePreparedDay(
              prepared,
              profile,
              dataNowSec,
              history,
              stopGeneration: stopGen,
            );
            done++;
          } else {
            failures++;
          }
        } catch (e) {
          if (DeriveStop.generation != stopGen) return;
          failures++;
          _log('rescan day $dayId FAILED/skipped: $e');
          // Do NOT mark-skipped here — a finalized day already has a good row;
          // overwriting it with a skip marker would DISCARD real structure.
        }
        completed++;
        onDayDone?.call(dayId, completed, orderedDays.length);
      }

      await runWithConcurrency(orderedDays, _deriveConcurrency, processDay);

      // A stopped rescan leaves the signature unstored so it runs again.
      DeriveStop.check(stopGen);
      await _refreshBaselines();
      // Cross-day rollup + notifications reflect the refreshed scalars.
      DeriveStop.check(stopGen);
      await _runCrossDay(profile);
      await _runNotifications();
      // Only acknowledge a complete refresh. A failed day keeps its old result
      // and must retry even when the baseline itself has not moved again.
      if (failures == 0) {
        await LocalDb.setCursor('baseline_sig', await _baselineSignature());
      } else {
        _log('rescan incomplete: $failures day(s) remain pending');
      }
      return done;
    } catch (e, st) {
      if (DeriveStop.generation != stopGen) {
        _log('rescan stopped: $e — runs again on the next opportunity');
        return 0;
      }
      _log('rescan ERROR: $e\n$st');
      return 0;
    } finally {
      if (DeriveStop.generation == stopGen) await _runStorageHousekeeping();
      _running = false;
    }
  }

  /// A stable, cheap signature of the CURRENT rolling baseline — the same inputs
  /// the readiness/illness baselines fold over. We take the trailing
  /// _baselineWindowDays derived rows and the median of each baseline series
  /// (RHR, RMSSD, skin-temp ADC mean, respiration), rounded to a stable
  /// precision, joined into a string. When new days land (or a recent day is
  /// re-derived) these medians shift and the signature changes → a rescan fires;
  /// when nothing moved the signature is byte-identical → the rescan is skipped.
  Future<String> _baselineSignature() async {
    final artifact = await LocalDb.baseline('rolling_artifact');
    final raw = artifact?['payload_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final sig = decoded['signature']?.toString();
          if (sig != null && sig.isNotEmpty) return sig;
        }
      } catch (_) {
        // Fall back to rebuilding the signature.
      }
    }
    final history = await _BaselineHistoryCache.load();
    return history.toArtifactJson()['signature']?.toString() ??
        'v$kAlgoVersion|na';
  }

  /// Foreground vs background pacing — lane count and per-day wall-clock
  /// budget. See [DerivePacing] for why the background numbers differ.
  DerivePacing get _pacing => DerivePacing(background: background);

  /// Max wall-clock for ONE day's off-isolate compute. On timeout the day is
  /// skipped so the sweep always makes progress.
  Duration get _perDayTimeout => _pacing.perDayTimeout;

  /// Throttle for the readiness-absent diagnostic log — one per calendar day
  /// so repeated light-pass re-derives of today don't spam the outbox.
  String? _loggedReadinessAbsentFor;

  /// Bounded worker-pool size for concurrent per-day derivation. Days within
  /// a single run share ONE frozen baseline snapshot (`_BaselineHistoryCache`
  /// is loaded once before the loop, refreshed once after — see `run()`) and
  /// each writes to an independent, day_id-keyed `day_result` row — there is
  /// no cross-day ordering dependency within a run. A multi-day backlog sweep
  /// was previously fully sequential (one day's prepare-isolate + prepare
  /// substrate loads + compute-isolate all finishing before the next day even
  /// started), which wastes every core beyond the one doing the current day's
  /// work. Running several days' isolate work genuinely concurrently gets
  /// real wall-clock speedup from the device's other cores — in the FOREGROUND.
  /// A headless background slot has no spare cores to soak up, so it takes one
  /// lane; [DerivePacing] owns that decision and explains it.
  int get _deriveConcurrency {
    try {
      return _pacing.concurrency(Platform.numberOfProcessors);
    } catch (_) {
      return 1; // Platform unavailable on this target — sequential fallback
    }
  }

  // ── imports (derive from a pre-built substrate, not from stored raw) ─────────

  /// Derive the named [dates] from a caller-supplied [sub] (e.g. a CSV import
  /// rebuilt into a Substrate), reusing the FULL per-day pipeline (sleep / HRV /
  /// strain / workouts / advanced_sleep) — so imported raw 1 Hz gets the exact
  /// same analytics as a live band sync. [sub] should span the requested dates
  /// PLUS the prior evening (a night's sleep starts before midnight, and the day
  /// model searches `prev 18:00 → noon`); the caller windows the stream so memory
  /// stays bounded. Each derived day is FORCE-FINALIZED (imports are immutable
  /// snapshots — there is no stored raw to recompute them from). Returns the
  /// number of days written. Does NOT prune raw or run the cross-day rollup —
  /// call [finalizeImport] once after all windows.
  Future<int> deriveImportedDays(
    Substrate sub,
    Profile profile,
    Set<String> dates, {
    void Function(String day)? onDayDone,
  }) async {
    if (sub.isEmpty || dates.isEmpty) return 0;
    final stopGen = DeriveStop.generation;
    // Under the SAME lock as run()/runDays(): this writes day_result rows, and
    // an import racing a background derive of the same day is exactly the
    // partial-overwrites-complete case the lock exists for.
    return _withRunLock(0, () async {
      await DayZoneStore.ensureRange(sub.tsSec.first, sub.tsSec.last);
      DeriveStop.check(stopGen);
      final days = calendarDays(sub);
      final dataNowSec = sub.lastTs ?? 0;
      var done = 0;
      for (final day in days) {
        DeriveStop.check(stopGen);
        if (!dates.contains(day.date)) continue;
        // NEVER clobber a day the band measured. `forceFinalize: true` below
        // both replaces the measured result and locks the day out of every
        // future re-derive, and the raw it came from is pruned within days —
        // so importing a file that overlaps real history destroyed it
        // silently and permanently. Same guard the WHOOP importer has always
        // had; it just was not shared.
        if (await LocalDb.isMeasuredDay(day.date)) {
          _log('import day ${day.date} kept (already measured on this device)');
          continue;
        }
        try {
          await _deriveDay(
            sub,
            day,
            profile,
            dataNowSec,
            forceFinalize: true,
            stopGeneration: stopGen,
          );
          done++;
          onDayDone?.call(day.date);
        } catch (e) {
          if (e is DeriveCancelled || DeriveStop.generation != stopGen) rethrow;
          _log('import day ${day.date} FAILED/skipped: $e');
        }
      }
      return done;
    });
  }

  /// Run the cross-day rollup + notifications + baseline refresh once after an
  /// import completes (reflects the freshly imported day history).
  /// NOT under [_withRunLock]: `_refreshBaselines` takes the lock itself, so
  /// holding it here would make this method skip its own first step. The rollup
  /// and notification passes below write one artifact each (last write wins,
  /// and the artifact is version/day stamped), so they are safe to interleave.
  Future<void> finalizeImport(Profile profile) async {
    await _refreshBaselines();
    await _runCrossDay(profile);
    await _runNotifications();
  }

  // ── derive one day ──────────────────────────────────────────────────────────

  Future<void> _deriveDay(
    Substrate sub,
    PhysioDay day,
    Profile profile,
    int dataNowSec, {
    bool forceFinalize = false,
    int? stopGeneration,
  }) async {
    final daySub = sub.slice(day.startSec, day.endSec);
    // Same buffered slice prepareDerivationPayload uses — without it, imported
    // days fall back to daySub and a nap straddling midnight is bisected again
    // on exactly the path this PR set out to fix.
    final napSub = sub.slice(day.startSec, day.endSec + napBoundaryBufferSec);
    final sleepSub = day.hasSleep
        ? sub.sliceIdx(day.sleepLoIdx, day.sleepHiIdx)
        : Substrate.empty;
    final hypno = day.sleep.stages4.isNotEmpty
        ? List<String>.from(day.sleep.stages4)
        : <String>[
            for (final s in day.sleep.stages)
              s == ana.SleepStage.wake
                  ? 'wake'
                  : (s == ana.SleepStage.rem ? 'rem' : 'light'),
          ];
    final win = day.sleep.window;
    final onsetSec = win == null
        ? 0
        : (win.onsetMs != null
              ? (win.onsetMs! / 1000).round()
              : (sleepSub.firstTs ?? 0));
    final offsetSec = win == null
        ? 0
        : (win.offsetMs != null
              ? (win.offsetMs! / 1000).round() + 1
              : ((sleepSub.lastTs ?? -1) + 1));
    await _derivePreparedDay(
      PreparedDerivationDay(
        date: day.date,
        endSec: day.endSec,
        confidence: day.confidence,
        flags: List<String>.from(day.flags),
        sleepJson: day.sleep.toJson(),
        hypnoStages: hypno,
        sleepOnsetSec: onsetSec,
        sleepOffsetSec: offsetSec,
        daySub: daySub,
        napSub: napSub,
        sleepSub: sleepSub,
      ),
      profile,
      dataNowSec,
      await _BaselineHistoryCache.load(),
      forceFinalize: forceFinalize,
      stopGeneration: stopGeneration,
    );
  }

  Future<void> _derivePreparedDay(
    PreparedDerivationDay day,
    Profile profile,
    int dataNowSec,
    _BaselineHistoryCache history, {
    bool forceFinalize = false,
    int? stopGeneration,
  }) async {
    // Keep the pass's generation through preparation/history reads. Taking a
    // fresh generation here would revive work stopped during those awaits.
    final stopGen = stopGeneration ?? DeriveStop.generation;
    DeriveStop.check(stopGen);
    final daySub = day.daySub;
    final sleepSub = day.sleepSub;
    // Per-second 4-class stage labels (the single source): 'wake'|'light'|
    // 'deep'|'rem'. analytics' segmentSleep exposes the 4-class stream directly
    // (NREM split into Light/Deep via the LOW-CONFIDENCE HR-depth overlay); we
    // pass it through verbatim so the UI can render Light vs Deep. Fall back to
    // the 3-class enum (light = plain NREM) only if stages4 is unexpectedly empty.
    // Resolved PER WINDOW, not per day: each span of the day goes to the best
    // source that actually covered it. Read HERE — before the pipeline input
    // is built — because BOTH energy passes price walking off these spans:
    // the pipeline's early-read mirror below and the second-half
    // `applyDayActivity`. One read, one span list, or the two figures drift.
    final liveSteps = await LocalDb.resolvedStepsForDay(day.date);
    final stepSpans = [
      for (final s in liveSteps.spans) [s.startTs, s.endTs, s.steps],
    ];
    final input = DayBundleInput(
      date: day.date,
      dayTsSec: daySub.tsSec,
      dayHr: daySub.hr,
      stepSpans: stepSpans,
      dayRrTsMs: daySub.rrTsMs,
      dayRrMs: daySub.rrMs,
      sleepTsSec: sleepSub.tsSec,
      sleepHr: sleepSub.hr,
      sleepRrTsMs: sleepSub.rrTsMs,
      sleepRrMs: sleepSub.rrMs,
      sleepRrCount: sleepSub.rrCount,
      sleepSkinTemp: sleepSub.skinTemp,
      sleepJson: day.sleepJson,
      hypnoStages: day.hypnoStages,
      sleepOnsetSec: day.sleepOnsetSec,
      sleepOffsetSec: day.sleepOffsetSec,
      profile: profile.toMap(),
      dayConfidence: day.confidence,
      dayFlags: day.flags,
      // WHICH STRAP measured this day, so the pipeline can dispatch its
      // per-family constants (today: the HR ceiling) and REFUSE on an unknown
      // family instead of borrowing gen4's.
      deviceFamily: daySub.deviceFamily,
      // Whether the sleep window was the user's own assertion or the detector's
      // guess — sleep-onset latency only means what people think it means on a
      // forced window.
      sleepSource: day.sleepSource,
    );
    final withHistory = _attachHistory(input, history)
      ..['day_context'] = DayClock.snapshot();

    // Cancellable: on timeout the isolate is KILLED, not merely abandoned to
    // keep burning a core behind the worker pool's back.
    final previous = _inputReuse[day.date];
    final cache = previous?.version == kAlgoVersion
        ? previous!
        : InputReuse(kAlgoVersion);
    final hitsBefore = cache.hits, missesBefore = cache.misses;
    final workerTime = Stopwatch()..start();
    DeriveStop.check(stopGen);
    final reused = await _runIsolateCancellable(
      () => (bundle: deriveDayBundle(withHistory, reuse: cache), cache: cache),
      _perDayTimeout,
      label: 'day-bundle ${day.date}',
    );
    DeriveStop.check(stopGen);
    workerTime.stop();
    _log(
      'day-bundle ${day.date}: ${workerTime.elapsedMilliseconds}ms, '
      '${reused.cache.hits - hitsBefore} reused, '
      '${reused.cache.misses - missesBefore} recalculated pure inputs',
    );
    _inputReuse.remove(day.date);
    _inputReuse[day.date] = reused.cache;
    while (_inputReuse.length > 3) {
      _inputReuse.remove(_inputReuse.keys.first);
    }
    final bundle = reused.bundle;
    // Readiness came back absent for TODAY specifically (not a historical
    // backfill day, which would just be noise): log the per-input reason the
    // isolate returned (onehz_pipeline.dart's readinessAbsentDiag), once a day.
    final absentDiag = bundle['readiness_absent_diag'];
    if (absentDiag != null &&
        day.date == LocalDb.localDayLabelNow() &&
        _loggedReadinessAbsentFor != day.date) {
      _loggedReadinessAbsentFor = day.date;
      _log('readiness absent for ${day.date}: $absentDiag');
    }

    // Where this day's sleep window came from (auto / auto_fallback / manual /
    // confirmed) — drives the Sleep screen's "is this right?" prompt + the
    // manual-edit affordance. Carried verbatim from the segmentation candidate.
    bundle['sleep_source'] = day.sleepSource;

    final scMap = (bundle['scalars'] as Map?)?.cast<String, dynamic>();

    // ── NEVER WRITE NOTHING OVER SOMETHING ───────────────────────────────────
    // Raw retention is 3 days, but derived history is forever — so a day older
    // than retention has a good `day_result` and NO raw. Re-deriving it (which
    // "Advanced data → Select all → Re-analyze" does for EVERY listed day, via
    // runDays(force: true) → _prepareTargetDay, whose empty substrate yields an
    // all-absent bundle) used to overwrite that good row: `putDayResult` is
    // ConflictAlgorithm.replace on BOTH `day_result` and `metric_series`, so
    // every scalar for the date was NULLed — and, because an empty bundle's
    // endSec was 0, the blank was written FINALIZED and could never re-derive.
    // Only `run()` had a pruned-raw guard, and only for user-override days.
    //
    // Detect it BEFORE the offloaded second half so its own writes
    // (wake_day_features) can't clobber the early-read path either. With no day
    // substrate and no sleep substrate the second half has nothing to add — its
    // scalars are all derived from those two.
    final producedNothing =
        daySub.isEmpty &&
        sleepSub.isEmpty &&
        (scMap == null || !scMap.values.any((v) => v != null));
    if (producedNothing) {
      final existing = await LocalDb.dayResult(day.date);
      if (_isRealDayResult(existing)) {
        _log(
          'derive ${day.date}: no substrate (raw pruned) — kept the '
          'existing result rather than blanking it',
        );
        return;
      }
    }

    // ── NEVER WRITE NIGHT-NULL OVER NIGHT-REAL (edge#305) ───────────────────
    // The guard above only catches a day with literally NOTHING. A day at the
    // retention-cutoff EDGE can have plenty of daytime HR (daySub non-empty)
    // while its sleep window's own RR/HR substrate has aged out from under it
    // (sleepSub empty) — sleep STAGING survives regardless (it replays the
    // durable `sleep_session_candidates` row, not raw), so `daySub`/`sleepSub`/
    // `scMap` all look like "something" and `producedNothing` is false — but
    // every night-physiology scalar (rhr/rmssd/readiness) comes back null.
    // `putDayResult` replaces `metric_series` wholesale (it's UNVERSIONED), so
    // this null silently overwrites a good historical baseline point and
    // collapses every later night's readiness baseline out from under it.
    //
    // v85 (edge#305 fully closed): this no longer requires THIS pass to have
    // found a sleep window. A re-stage whose RR/HR substrate aged out can come
    // back with no window at all (`NO_SLEEP_DETECTED`), not just a truncated
    // one — that shape is exactly as much a regression against an existing
    // real result, and v83's `hasSleepWindow` requirement missed it (the exact
    // counterexample #305 named). What actually distinguishes this from an
    // honest "this day never had sleep" derive is the existingHadNight check
    // right below, not whether this pass sees a window — a day that never had
    // real sleep never had an existing result with real night scalars either.
    // Decline the same way: keep the existing (older-version) row being served
    // (`_servedDayJoin` already serves the highest version <= ceiling, so
    // nothing needs to change there) rather than writing a new, worse row. A
    // `partial` row was considered instead, but `partial` still gets written
    // to `day_result` and would still shadow the better older row for
    // day-detail reads; declining is what actually protects it.
    if (!producedNothing &&
        nightSubstrateRegressed(
          sleepSubEmpty: sleepSub.isEmpty,
          nightScalarsNull:
              scMap == null ||
              (scMap['rhr'] == null &&
                  scMap['rmssd'] == null &&
                  scMap['readiness'] == null),
        )) {
      final existingNight = await LocalDb.dayResult(day.date);
      final existingHadNight =
          existingNight != null &&
          (existingNight['rhr'] != null ||
              existingNight['rmssd'] != null ||
              existingNight['readiness'] != null);
      if (existingHadNight) {
        _log(
          'derive ${day.date}: sleep-window substrate pruned out from '
          "under a day that already had real night scalars — kept the "
          'existing result rather than nulling the readiness baseline '
          '(edge#305)',
        );
        return;
      }
    }

    // ── SECOND HALF — OFFLOADED to a background isolate ──────────────────────
    // Everything that turns the isolate-1 bundle into the full day result (wake
    // features, hybrid steps + TDEE, all-day HRV/RSA/skin-temp Timeline lines,
    // naps, workout detection + HRR, wrist orientation, restlessness map, fit
    // quality) used to run on the CALLING isolate — the UI isolate for the
    // foreground light pass that fires on every sync — hanging the main thread
    // for seconds (the rolling-RSA Lomb-Scargle over the 24 h day + nap
    // re-staging + workout detection are the trig/CPU hogs). It is all PURE
    // compute over the two substrates + a few scalars, so it now runs in
    // Isolate.run. DB reads that it needs are done HERE (this is the DB-owning
    // isolate); the DB writes + notification it produces are returned as
    // descriptors and applied below. Same _perDayTimeout guard as isolate 1.
    // NON-FATAL: a failure OR timeout anywhere in the offloaded second half must
    // never skip the whole day. Isolate 1 already computed the headline scalars
    // (readiness / RHR / RMSSD) into bundle['scalars']; we persist those and just
    // drop the optional detail blocks. (Previously an exception here threw out of
    // _derivePreparedDay → the day was marked skipped → readiness rendered "-"
    // even though it had been computed fine — the "readiness randomly goes -" bug.)
    // `secondHalfOk` tracks whether this actually completed: a headline-only
    // row must be marked `partial` below so it never locks as finalized and
    // never counts as "derived" for the raw-pruning guard (see
    // LocalDb.dayResultIds) — otherwise a transient failure here permanently
    // loses the ability to ever back-fill naps/workouts/HRR/wear/curves for
    // this day once its raw substrate is pruned.
    var secondHalfOk = true;
    try {
      final dayLo = daySub.length == 0 ? 0 : daySub.tsSec.first;
      final dayHi = daySub.length == 0 ? 0 : daySub.tsSec.last + 60;
      // `liveSteps`/`stepSpans` were read above, before the pipeline input —
      // one resolution serves both energy passes. `.strap` is carried
      // alongside the total so the bundle can name the sensor that counted.
      //
      // Sessions are queried over the FULL local calendar day, not
      // [dayLo, dayHi] — those bounds come from daySub's own first/last
      // sample, so a completed session the band's PPG lost contact for
      // entirely (zero HR samples at all, e.g. a wrist-gripping lift) can
      // fall outside them and never reach the zero-coverage credit below.
      final savedSessions = await LocalDb.sessionsInRange(
        _localDayLabelToSec(day.date),
        localNextMidnightSecForDayLabel(day.date),
      );

      // Off-wrist / charging spans over the NAP window (which runs past this
      // day's end), read here because the isolate has no DB handle. These are
      // the strap's own reports: a band on a table or a charger is perfectly
      // still and otherwise reads as deep rest to a motion-based detector.
      final napLo = day.napSub.length == 0 ? dayLo : day.napSub.tsSec.first;
      final napHi = day.napSub.length == 0 ? dayHi : day.napSub.tsSec.last + 60;
      // ...and back to SLEEP ONSET, which is routinely EARLIER than napLo. This
      // day's sleep is the night that ENDED this morning, so its onset sits at
      // ~23:00 YESTERDAY — before local midnight, before the day's first
      // record. `_toggleSpans` carries an already-open state in from before its
      // window, so a charge that straddles midnight was always covered; one
      // that opened AND closed at 23:20 was invisible. That is the shape of a
      // battery-pack top-up before bed, i.e. the exact case this feeds.
      final spanLo = day.sleepOnsetSec > 0
          ? math.min(napLo, day.sleepOnsetSec)
          : napLo;
      final wearLo = math.min(spanLo, _localDayLabelToSec(day.date));
      final wearHi = math.max(napHi, localNextMidnightSecForDayLabel(day.date));
      final wristOffSpans = await LocalDb.wristOffSpans(wearLo, wearHi);
      final chargingSpans = await LocalDb.chargingSpans(wearLo, wearHi);

      // PERSONAL movement floor — ESTIMATED ONCE, THEN FROZEN.
      //
      // Freezing is the whole point and it is not an optimisation. This
      // threshold is derived from the same signal it thresholds, so a floor
      // that keeps tracking the user cancels the trend it exists to report.
      // Measured by scaling a real day's dynAmp and recomputing both ways:
      //
      //     activity x     FROZEN     recomputed
      //          1.00          23             37
      //          1.50          66             37
      //          2.00         128             37
      //          3.00         254             37
      //
      // A recomputed floor reports the SAME number whether the user tripled
      // their activity or did nothing at all. So: accumulate `dyn_p90` for an
      // enrollment window, commit the median, and keep using it. It re-freezes
      // only on events that genuinely change the signal's scale (see
      // `ana.shouldRefreezeFloor`) — never merely because time passed.
      //
      // Self-exclusion (days STRICTLY BEFORE this one) is retained for the
      // enrollment estimate: a day must not help set the threshold it is then
      // scored against. Below the minimum history the floor is null and the
      // estimator abstains rather than substituting a constant.
      final dynFloorG = await _frozenMovementFloor(history, day.date);
      final dynHistory = history.valuesBefore('dyn_p90', day.date);

      // Built on THIS isolate so the Isolate.run closure captures only this plain
      // sendable object (never `this`, `day`, or `bundle`).
      // Read HERE, on the main isolate — the worker has no database.
      final napEdits = [
        for (final row in await LocalDb.napEdits(day.date))
          NapEdit(
            kind: row['source'] == 'rejected'
                ? NapEditKind.rejected
                : NapEditKind.added,
            startSec: (row['start_ts'] as num).toInt(),
            endSec: (row['end_ts'] as num).toInt(),
          ),
      ];

      final blocksInput = _DayBlocksInput(
        daySub: daySub,
        napSub: day.napSub,
        napEdits: napEdits,
        sleepSub: sleepSub,
        profile: profile,
        onsetSec: day.sleepOnsetSec,
        offsetSec: day.sleepOffsetSec,
        // NOCTURNAL-ONLY. `scalars.rhr` is allowed to fall back to daytime HR
        // for the resting-HR card; feeding that into TRIMP charged a day
        // against an awake reference and published a strain the pure pipeline
        // had already refused to publish. `rhr_nocturnal` is null unless a
        // sleep session was detected — exactly the gate readiness uses.
        rhr: (scMap?['rhr_nocturnal'] as num?)?.toDouble(),
        maxHrUsed: (bundle['max_hr_used'] as num?)?.round(),
        // B88-02: THE zone set the pure pipeline banded `zone_timeline` and
        // `zone_source` on — same inputs, same function — so the day's zone
        // bars and the label beside them are one definition.
        zoneSet: trainingZones(
          age: profile.ageYears,
          deviceFamily: daySub.deviceFamily,
          observedCeilingBpm: (withHistory['observed_hr_ceiling_bpm'] as num?)
              ?.toDouble(),
          restingHrHistory: [
            for (final v in (withHistory['rhr_history'] as List?) ?? const [])
              if (v is num) v.toDouble(),
          ],
        ),
        liveStepsReal: liveSteps.total,
        liveStepsFromStrap: liveSteps.strap,
        // The same resolution's credited spans, so the walking-cadence term
        // prices exactly the steps the day's total already counted — never a
        // raw row the ladder took back.
        stepSpans: stepSpans,
        dynFloorG: dynFloorG,
        dynHistoryDays: dynHistory.length,
        savedSessions: savedSessions,
        wristOffSpans: wristOffSpans,
        chargingSpans: chargingSpans,
        mainTstMin: (scMap?['tst_min'] as num?)?.round(),
        // The scalar is a PERCENT (onehz_pipeline.dart:914); the period
        // contract and the card both want 0..1, the same normalization
        // `_daySleep` does on read.
        mainEfficiency: (scMap?['efficiency'] as num?) == null
            ? null
            : (scMap!['efficiency'] as num).toDouble() / 100.0,
        date: day.date,
        // Local midnight from the day LABEL, not from the substrate — this has
        // to be where `napSub`'s slice window opens (`_localDayLabelToSec`),
        // not where its first surviving sample happens to land, or the
        // contiguity test compares a timestamp against itself and is
        // vacuously true on every day with a gap at the boundary.
        dayStartSec: _localDayLabelToSec(day.date),
        dayEndSec: day.endSec,
        dataNowSec: dataNowSec,
        viewNowSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        dayContext: DayClock.snapshot(),
      );
      DeriveStop.check(stopGen);
      final blocks = await _runDayBlocksCancellable(
        blocksInput,
        _perDayTimeout,
      );
      DeriveStop.check(stopGen);

      // Merge the computed blocks back into the isolate-1 bundle. scMap is the
      // CastMap view over bundle['scalars'], so addAll writes through — nap_min /
      // hrr_bpm reach the persisted series map below.
      // `addAll` REPLACES `absent_notes` wholesale, and the two halves own
      // different keys: `trimp` is only ever the pure pipeline's (nothing in the
      // second half recomputes it), while strain/zones/calories/max_hr_used are
      // the recompute's. Keep the pipeline's trimp reason across the merge or
      // the Activity screen's "training load" goes absent with nothing to say.
      final trimpNote = (bundle['absent_notes'] as Map?)?['trimp'] as String?;
      bundle.addAll(blocks.bundlePatch);
      if (trimpNote != null && (bundle['scalars'] as Map?)?['trimp'] == null) {
        (bundle['absent_notes'] as Map?)?['trimp'] = trimpNote;
      }
      (bundle['series'] as Map?)?.cast<String, dynamic>().addAll(
        blocks.seriesPatch,
      );
      scMap?.addAll(blocks.scalarPatch);

      // ONE ANSWER FOR STRAIN. The second half just recomputed it from the same
      // nocturnal-or-user resting HR the pure pipeline gated on, and its scalar
      // is what every surface reads. When that recompute abstains, stamp
      // `clinical.strain` absent alongside the null scalar: the two were
      // written by different code paths off different resting HRs, and a stored
      // bundle could hold "—" in one and a confident 5.99 in the other.
      if (scMap != null && scMap['strain'] == null) {
        final strainEnv = (bundle['clinical'] as Map?)?['strain'];
        if (strainEnv is Map) {
          strainEnv['value'] = '—';
          strainEnv['confidence'] = 0;
          // The note is stamped even when the envelope was ALREADY absent. It
          // used to be gated on `value != '—'`, so on every day where both
          // halves abstained — which is every day this matters on — the reason
          // never landed and the envelope kept the scorer's "strain needs a
          // TRIMP", naming a sibling metric instead of the missing input.
          strainEnv['note'] =
              blocks.wake['strain_absent'] ?? kUnknownAbsenceNote;
        }
      }

      // DB writes + notification the pure compute deferred to us (DB-owning isolate).
      for (final w in blocks.sessionHrrWrites) {
        await LocalDb.setSessionHrr(w.$1, w.$2);
        onSessionChanged?.call();
      }
      for (final sug in blocks.suggestionsToPersist) {
        await LocalDb.putWorkoutSuggestion({
          ...sug,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      final nb = blocks.notifBout;
      // Only for a bout that is STILL waiting on an answer. The detector is
      // pure and re-derives the same bouts every pass; dismissing one, logging
      // it, or logging any session that covers its window retires the row
      // (`supersededSuggestionIds`), and none of that reaches the detector. So
      // the live table is what decides, not the detection — a notification
      // about a workout already in the log is how someone turns all of them
      // off. `putWorkoutSuggestion` ran a few lines up, so the row is there.
      final live = nb == null
          ? false
          : (await LocalDb.activeWorkoutSuggestions()).any(
              (r) => r['id'] == nb.id,
            );
      if (nb != null && live) {
        await NotificationCenter.instance.emit(
          NotificationEvent(
            // Per-bout, not per-day — a per-day key silently swallowed the
            // notification for a second real workout later the same day
            // (fire-once-per-key by design). The suggestion id is stable across
            // re-derive passes re-detecting the SAME bout, so that case still
            // dedupes, and it is date-prefixed so the fired-key store prunes it.
            dedupeKey: '${nb.id}:auto_workout',
            // NOT `recovery`. That channel is where "your recovery is ready"
            // lived and `classOf` drops everything on it, so this notification
            // has never once reached anybody: the suggestion row was written,
            // the user was never told. This is a prompt about something that
            // happened — reminders channel, NotifClass.prompt, and it respects
            // quiet hours like every prompt should.
            category: NotifCategory.reminders,
            priority: NotifPriority.normal,
            title: 'Did you work out?',
            body:
                'We spotted ~${nb.durationMin} min of elevated activity. '
                'Tap to log it.',
            date: day.date,
            route: workoutSuggestionRoute(nb.id),
          ),
          // This runs from headless background derivation too — never prompt
          // for permission from a background context (violates the OS
          // background contract and can incorrectly cache permission=denied).
          allowPermissionPrompt: false,
        );
      }

      await _persistWakeDayFeatures(dayId: day.date, wake: blocks.wake);
    } catch (e) {
      if (e is DeriveCancelled || DeriveStop.generation != stopGen) rethrow;
      secondHalfOk = false;
      _log(
        'day-blocks (offloaded second half) failed for ${day.date} — '
        'persisting headline day (partial): $e',
      );
    }

    // Finalize once the DATA EDGE has moved >48 h past the day's wake — i.e. we
    // have continuous drained data well beyond it, so no more flash can land for
    // this day. (Anchored on the last record ts, NOT the wall clock.) Imports
    // force-finalize: there is no stored raw to ever recompute them from, so
    // forceFinalize wins even for a partial (headline-only) result — there's
    // nothing left to retry regardless. Outside of that, never let a partial
    // result lock in as finalized purely by age, or its missing naps/
    // workouts/HRR/wear/curves would never get a chance to be filled in by a
    // later retry.
    final ageFinalized = (day.endSec + _finalizationSec) < dataNowSec;
    // A result with NOTHING in it is never finalized — not even by
    // forceFinalize. Locking an all-absent row is what made the destructive
    // re-analyze permanent; leaving it unlocked means a later pass (or a
    // restored/backfilled substrate) can still fill the day in.
    final finalized =
        !producedNothing && (forceFinalize || (ageFinalized && secondHalfOk));

    // A failed/timed-out second half yields a headline-only bundle, and
    // putDayResult replaces the row wholesale — so re-deriving an already
    // complete day (rescanRecent deliberately revisits finalized days) destroyed
    // its naps, sleep periods, workouts, HRR, wear and curves. Carry the
    // previous result's detail forward instead of blanking it. Same principle as
    // the producedNothing guard above and the skip-marker guard in
    // _markDaySkipped: never let a thinner result overwrite a richer one.
    var effectiveFinalized = finalized;
    var effectivePartial = !secondHalfOk;
    if (!secondHalfOk) {
      final existing = await LocalDb.dayResult(day.date);
      if (_isRealDayResult(existing)) {
        final prev = _decodeBundle(existing!['payload_json']);
        if (prev != null) {
          final recovered = carryForwardDetail(prev, bundle);
          final prevVersion = (existing['algo_version'] as num?)?.toInt();
          final outcome = recoveryOutcome(
            recovered: recovered,
            prevPartial: (existing['partial'] as num?)?.toInt() == 1,
            prevVersion: prevVersion,
            prevFinalized: (existing['finalized'] as num?)?.toInt() == 1,
            finalizedByAge: finalized,
          );
          effectivePartial = outcome.partial;
          effectiveFinalized = outcome.finalized;
          _log(
            'derive ${day.date}: second half failed — carried the previous '
            "result's detail blocks forward (v$prevVersion -> v$kAlgoVersion, "
            'partial=$effectivePartial)',
          );
        }
      }
    }

    final scalars =
        (bundle['scalars'] as Map?)?.cast<String, dynamic>() ?? const {};
    double? sc(String k) => (scalars[k] as num?)?.toDouble();
    DeriveStop.check(stopGen);
    await LocalDb.putDayResult(
      dayId: day.date,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(bundle),
      windowJson: jsonEncode(
        ((day.sleepJson['window'] as Map?) ?? const {}).cast<String, dynamic>(),
      ),
      finalized: effectiveFinalized,
      partial: effectivePartial,
      rhr: sc('rhr'),
      rmssd: sc('rmssd'),
      readiness: sc('readiness'),
      // export-provenance: this day's scalars came out of the 1 Hz substrate
      // the strap recorded. An importer's day is a DIFFERENT vendor's derived
      // score and must carry its own tag; a day whose provenance is genuinely
      // unknown stays NULL and is never retro-filled with this.
      source: 'band',
      // WHICH BAND'S UNITS these scalars are in (B5). Already null when the
      // day's substrate spans two straps or carries no stamp — the same
      // "unknown, never guessed" value the column is documented with.
      deviceFamily: daySub.deviceFamily,
      series: {
        'rhr': sc('rhr'),
        'rmssd': sc('rmssd'),
        'sdnn': sc('sdnn'),
        'readiness': sc('readiness'),
        'ln_rmssd': sc('ln_rmssd'),
        'ln_rmssd_v2': sc('ln_rmssd_v2'),
        'resp_rate': sc('resp_rate'),
        'skin_temp_z': sc('skin_temp_z'),
        // RAW nightly ADC mean — the baseline series for skin_temp_z. Written
        // EVERY day (even during the bootstrap window where skin_temp_z is null)
        // so the baseline fills and z begins computing from ~day 4.
        'skin_temp_adc': sc('skin_temp_adc'),
        'dip_pct': sc('dip_pct'),
        // Headline 0–21 strain (for trend/sparkline); raw TRIMP kept too.
        // Written even when NULL: an abstaining day must overwrite a value a
        // previous version's daytime-RHR strain left behind, not keep it.
        'strain': sc('strain'),
        'trimp': sc('trimp'),
        // `strain_effort`, `spo2` and `odi_per_hour` used to be listed here.
        // Nothing in the tree ever produced them (12 rows, 0 values per key on
        // a real install), so they were three permanently-null series with a
        // card-less key in the coach's contract. A metric this app does not
        // produce has no entry and no key — the same rule metric_detail.dart
        // states and the UI already followed.
        // New metrics → trends (day/week/month/3M).
        'stress': sc('stress'),
        'calories': sc('calories'),
        // Steps = REAL pedometer counts only (band 100 Hz / phone / NOOP
        // import, all via `live_coverage`). Absent — written as a NULL row, so
        // a previously fabricated value is overwritten rather than left
        // standing — on any day nothing gait-capable measured.
        'steps': sc('steps'),
        // Movement minutes: activity VOLUME, not locomotion. Steps are NOT
        // derived from this and never will be again (see the v55/v56 note).
        'active_min': sc('active_min'),
        // This day's high quantile of the calibration-invariant dynamic accel
        // amplitude. Not a user-facing metric: it is the per-day summary the
        // NEXT day's derive pools to anchor its personal ambulatory floor, so
        // the threshold never depends on a single day (see _BaselineHistoryCache).
        'dyn_p90': sc('dyn_p90'),
        'calories_total': sc('calories_total'),
        // Daytime nap minutes (principled van Hees + HR-dip) → trend + Sleep Coach.
        'nap_min': sc('nap_min'),
        // Sleep-stage minutes + HRV freq/stability trends.
        'rem_min': sc('rem_min'),
        'deep_min': sc('deep_min'),
        'light_min': sc('light_min'),
        'tst_min': sc('tst_min'),
        'lf_hf': sc('lf_hf'),
        'hrv_cv': sc('hrv_cv'),
        'efficiency': sc('efficiency'),
        'worn_min': sc('worn_min'),
        // v25: 24/7 irregular-rhythm screen flag, breathing-rate variability,
        // and mean heart-rate recovery across the day's detected bouts.
        'irregular_rhythm_flag': sc('irregular_rhythm_flag'),
        'brv_cv': sc('brv_cv'),
        'hrr_bpm': sc('hrr_bpm'),
        // Recovery time constant (s) from the same tail `hrr_bpm` comes off.
        // Alongside it, never instead of it — the fit gate abstains often.
        'hrr_tau_s': sc('hrr_tau_s'),
        // Deceleration capacity (ms), personal trend only — no reference range,
        // no colour, no threshold, ever.
        'prsa_dc': sc('prsa_dc'),
        // How much of the sleep window the temp channel actually covered.
        'skin_temp_coverage_frac': sc('skin_temp_coverage_frac'),
        // Sleep shape: hours nobody watched, sustained awakenings (a floor),
        // longest unbroken stretch, and forced-window sleep-onset latency.
        'unobserved_min': sc('unobserved_min'),
        'awakenings': sc('awakenings'),
        'longest_sleep_min': sc('longest_sleep_min'),
        'sol_min': sc('sol_min'),
        // SLP-09 / L10 — where on the clock the night sat, tz-corrected and
        // UNWRAPPED (signed seconds either side of 04:00 local; see
        // onehz_pipeline's sleepClockOffsetSec). Written so a schedule-shift
        // segmentation has a series to run on in six months. FORWARD-ONLY:
        // mid-sleep was never persisted, the 1 Hz substrate it comes from is
        // gone at 3 days, and days lock ~48 h after wake — so every night
        // before this shipped has no value and cannot be given one.
        'midsleep_sec': sc('midsleep_sec'),
        'sleep_onset_sec': sc('sleep_onset_sec'),
        // TS-03 — this day's observed HR ceiling (bpm), or NULL on the ordinary
        // day that held none. The app-wide "highest we've seen" is the max of
        // this series; the date/session behind it lives in that day's bundle.
        'hr_ceiling_bpm': sc('hr_ceiling_bpm'),
      },
    );
    // NOTE: the sweep's `history` snapshot is deliberately NOT updated here.
    // See _BaselineHistoryCache — mutating the shared snapshot mid-sweep is the
    // duplicate-day pollution bug, and each day already derives its own
    // date-bounded window from the frozen snapshot.
    _log(
      'derived ${day.date} v$kAlgoVersion '
      '(sleep=${day.sleepOffsetSec > day.sleepOnsetSec}, final=$finalized)',
    );
    await _maybeFreezeHeadlineReadiness(
      day,
      dataNowSec,
      sc('readiness'),
      bundle: bundle,
      historyInputs: withHistory,
      history: history,
    );
  }

  /// Pin today's morning readiness headline once its overnight is genuinely
  /// COMPLETE, so the Today hero + recovery story stop drifting through the day
  /// (#128). Only the headline is pinned — this row's `day_result`, the
  /// baselines, trends and finalisation all keep updating on later re-derives.
  Future<void> _maybeFreezeHeadlineReadiness(
    PreparedDerivationDay day,
    int dataNowSec,
    double? readiness, {
    required Map<String, dynamic> bundle,
    required Map<String, dynamic> historyInputs,
    required _BaselineHistoryCache history,
  }) async {
    // Only today's headline is pinned. Historical/backfill + imported days never
    // reach the Today hero, and imports are immutable snapshots anyway.
    if (day.date != todayLabel()) return;
    final hasSleep = day.sleepOffsetSec > day.sleepOnsetSec;
    if (!hasSleep) return;
    final overnightComplete =
        dataNowSec >= day.sleepOffsetSec + _headlineFreezeMarginSec;
    final current = await LocalDb.frozenHeadline();
    final next = nextFrozenHeadline(
      today: day.date,
      overnightComplete: overnightComplete,
      liveReadiness: readiness?.round(),
      current: current,
    );
    if (next == null) return;
    // Already pinned to this exact value → skip the redundant write.
    if (current != null &&
        current.day == next.day &&
        current.value == next.value) {
      return;
    }
    await LocalDb.setFrozenHeadline(
      next.day,
      next.value,
      explanation: recoveryExplanationSnapshot(
        bundle,
        historyInputs,
        day: day.date,
        hrvHistory: history._series['ln_rmssd_v2'] ?? const [],
      ),
    );
    _log('froze headline readiness ${next.value} for ${next.day}');
  }

  /// Skip reasons that describe a TRANSIENT failure of this particular pass
  /// rather than a permanently pathological day. These must never finalize:
  /// finalizing locks the day out of every future pass at this algo version.
  static const Set<String> _transientSkipReasons = {'timeout', 'error'};

  /// edge#305 — whether THIS derive's night-physiology substrate has
  /// regressed to nothing even though [producedNothing] (in
  /// `_derivePreparedDay`) is false: plenty of daytime HR survives, but
  /// [sleepSubEmpty] (the night's own RR/HR substrate) is gone and every
  /// night-physiology scalar ([nightScalarsNull]) came back null. Deliberately
  /// NOT gated on this pass finding a sleep window: v83 required
  /// `hasSleepWindow` and missed the exact counterexample #305 named — a
  /// re-stage whose RR/HR substrate aged out can come back `NO_SLEEP_DETECTED`
  /// too, not just a truncated-but-present window, and that shape is just as
  /// much a regression against an existing real result. A genuinely-honest
  /// "this day never had sleep" case is still safe: it never had an existing
  /// result with real night scalars, so the caller's existing-result check is
  /// what actually distinguishes the two, not this shape test. Pure so the
  /// shape is unit-testable without the full pipeline; the caller still has to
  /// confirm an EXISTING result actually had real night scalars before
  /// declining to write over it.
  static bool nightSubstrateRegressed({
    required bool sleepSubEmpty,
    required bool nightScalarsNull,
  }) => sleepSubEmpty && nightScalarsNull;

  /// Whether [row] is a REAL derived day result worth protecting — i.e. not a
  /// skip marker and not an all-absent shell.
  static bool _isRealDayResult(Map<String, dynamic>? row) {
    if (row == null) return false;
    if ((row['skipped'] as num?)?.toInt() == 1) return false;
    final payload = _decodeBundle(row['payload_json']);
    if (payload == null) return false;
    if (payload['skipped'] == true) return false;
    final scalars = payload['scalars'];
    if (scalars is Map && scalars.values.any((v) => v != null)) return true;
    return row['rhr'] != null ||
        row['rmssd'] != null ||
        row['readiness'] != null;
  }

  /// Fill [next]'s missing detail from [prev] when the second-half compute
  /// failed, so a headline-only pass never blanks a day that already had naps,
  /// workouts, HRR, wear and curves. Returns true if anything was carried over.
  ///
  /// Keyed on ABSENCE, not on null: isolate 1 writes its headline scalars
  /// explicitly and a null there is a real "we could not measure this today"
  /// that must survive. Only keys the failed second half never got to add are
  /// restored — a freshly computed value always wins.
  @visibleForTesting
  static bool carryForwardDetail(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    var carried = false;
    for (final e in prev.entries) {
      if (e.key == 'scalars' || e.key == 'series') continue;
      if (next.containsKey(e.key) || e.value == null) continue;
      next[e.key] = e.value;
      carried = true;
    }
    // `scalars` and `series` are flat maps the second half patches INTO rather
    // than owning, so they merge per key instead of wholesale.
    for (final sub in const ['scalars', 'series']) {
      final p = prev[sub];
      if (p is! Map) continue;
      final n = next[sub];
      if (n is! Map) {
        next[sub] = Map<String, dynamic>.from(p.cast<String, dynamic>());
        carried = true;
        continue;
      }
      for (final e in p.entries) {
        if (n.containsKey(e.key) || e.value == null) continue;
        n[e.key] = e.value;
        carried = true;
      }
    }
    return carried;
  }

  /// The night's measured total sleep, seconds. Null when this candidate has no
  /// night in it at all.
  static num? _tstSec(SleepSessionCandidate c) =>
      c.sleepJson['tst_sec'] as num?;

  /// Whether the already-banked [prev] night is RICHER than the freshly staged
  /// [next] one, measured by total sleep time (#242).
  ///
  /// TST, not confidence and not the window: it is the quantity the user sees
  /// change, and the failure mode this guards is a re-stage over a pruned
  /// substrate seeing less of the same night. A night that grows is a night the
  /// band handed over more of, and it wins.
  ///
  /// A candidate with no night at all is never richer than one that has one, and
  /// EQUAL is not richer — a pass that reproduces the same night writes, so an
  /// otherwise-identical candidate still refreshes.
  @visibleForTesting
  static bool isRicherSleep(
    SleepSessionCandidate prev,
    SleepSessionCandidate next,
  ) {
    final p = _tstSec(prev);
    if (p == null) return false;
    final n = _tstSec(next);
    return n == null || p > n;
  }

  /// How a day should be filed after its second half failed and the previous
  /// result's detail was carried forward.
  ///
  /// The version check is the subtle part. `LocalDb.dayResult` returns the
  /// HIGHEST algo_version stored for the day, so immediately after a bump the
  /// row it hands back belongs to the previous version. Carrying that detail
  /// forward still beats blanking the day — but it must not be filed as a
  /// finished CURRENT-version result, because the reason a bump exists is that
  /// those blocks are computed differently now. A cross-version carry therefore
  /// stays partial and unfinalized, so a later pass recomputes it for real
  /// instead of locking last version's curves in under this version's number.
  @visibleForTesting
  static ({bool partial, bool finalized}) recoveryOutcome({
    required bool recovered,
    required bool prevPartial,
    required int? prevVersion,
    required bool prevFinalized,
    required bool finalizedByAge,
  }) {
    final sameVersion = prevVersion == kAlgoVersion;
    if (!recovered || prevPartial || !sameVersion) {
      // Stays partial, but keep whatever the caller had already decided about
      // finalizing: an IMPORT force-finalizes even a partial day, because there
      // is no stored raw to ever recompute it from.
      return (partial: true, finalized: finalizedByAge);
    }
    // As complete as it was before this pass, so it keeps what it had earned.
    return (partial: false, finalized: finalizedByAge || prevFinalized);
  }

  /// Test seam for [_markDaySkipped] — the "a skip marker must never destroy a
  /// real result" guarantee is the whole point of the method, so it is pinned
  /// directly rather than through a full derive pass.
  @visibleForTesting
  Future<void> debugMarkDaySkipped(
    String dayId,
    int dayEndSec,
    int dataNowSec, {
    required String reason,
  }) => _markDaySkipped(dayId, dayEndSec, dataNowSec, reason: reason);

  /// Persist a minimal skip marker so a pathological day isn't retried forever.
  ///
  /// A SKIP MARKER MUST NEVER OVERWRITE A REAL RESULT. `putDayResult` is
  /// ConflictAlgorithm.replace on both `day_result` AND `metric_series`, so this
  /// used to blank a good day's every scalar on a single [_perDayTimeout]
  /// overrun — and, once the day sat >48 h behind the data edge, wrote the blank
  /// FINALIZED, making it permanent (raw is pruned 3 days later, so there is
  /// nothing left to re-derive from). It hit TODAY too: a good 08:00 result
  /// replaced by a skip marker after one transient 09:00 timeout on a loaded
  /// phone. `rescanRecent` explicitly refuses to do this for exactly this
  /// reason; `run()` did it anyway. Now: write the marker only when there is no
  /// good row to lose, and never lock a transient failure.
  Future<void> _markDaySkipped(
    String dayId,
    int dayEndSec,
    int dataNowSec, {
    required String reason,
  }) async {
    try {
      final existing = await LocalDb.dayResult(dayId);
      if (_isRealDayResult(existing)) {
        _log(
          'derive $dayId $reason — existing result kept (not overwritten '
          'with a skip marker)',
        );
        return;
      }
      await LocalDb.putDayResult(
        dayId: dayId,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({'skipped': true, 'reason': reason}),
        windowJson: '{}',
        // Structural failures (a day that can never be prepared / blows the
        // prepare budget) still finalize once aged out, so they aren't retried
        // forever. A timeout or a one-off error does not — that day gets
        // another chance while it still has raw.
        finalized:
            !_transientSkipReasons.contains(reason) &&
            (dayEndSec + _finalizationSec) < dataNowSec,
        skipped: true,
      );
    } catch (_) {
      /* best-effort */
    }
  }

  /// Attach trailing personal history (from metric_series) for the readiness
  /// pass — the trailing window of days STRICTLY BEFORE the day being derived.
  ///
  /// The self-exclusion (`date < input.date`) is load-bearing, not cosmetic: see
  /// [_BaselineHistoryCache.valuesBefore]. Every one of these series is a
  /// BASELINE the day's own value is scored against, so the day's own row (which
  /// a previous derive of the same day already persisted) must not be in it.
  Map<String, dynamic> _attachHistory(
    DayBundleInput input,
    _BaselineHistoryCache history,
  ) {
    final m = input.toJson();
    final date = input.date;
    // B88-03/10: new-method nights only; earlier `ln_rmssd` used a different
    // (gap-bridging, sparse-admitting) estimator.
    m['ln_rmssd_history'] = history.valuesBefore('ln_rmssd_v2', date);
    m['rhr_history'] = history.valuesBefore('rhr', date);
    m['resp_history'] = history.valuesBefore('resp_rate', date);
    // Robust nocturnal RMSSD history (the `rmssd` series) — feeds the EWMA hrv
    // baseline so its center matches today's headline RMSSD (same metric).
    m['rmssd_history'] = history.valuesBefore('rmssd', date);
    // BASELINE for skin_temp_z is the RAW nightly ADC-mean series (`skin_temp_adc`),
    // NOT the z-score series. Feeding z-scores back as the baseline was a unit
    // mismatch that left z permanently null. The raw mean is stored every day so
    // this series fills and z starts computing once ≥3 days exist.
    m['skin_temp_adc_history'] = history.valuesBefore('skin_temp_adc', date);
    m['tst_history'] = history.valuesBefore('tst_min', date);
    // TS-03/TS-04 — the observed ceiling this day's ZONES are banded on. A max,
    // not a window (see [maxBefore]), and strictly before today so a day is
    // never banded on a ceiling its own session set.
    m['observed_hr_ceiling_bpm'] = history.maxBefore('hr_ceiling_bpm', date);
    return m;
  }

  // ── cross-day rollup ─────────────────────────────────────────────────────────

  static const Duration _crossDayTimeout = Duration(seconds: 30);
  static const int _crossDayWindow = 90;

  /// Whether a persisted `crossday_input` artifact may be reused AS-IS today.
  ///
  /// Pure, so it is unit-testable without a database — the seam that consumes it
  /// ([_crossDayInputDays]) cannot be.
  ///
  /// The artifact stamps `is_today: true` on the row that was today WHEN IT WAS
  /// BUILT. That is a fact about a day stored as a bare boolean, in a DURABLE
  /// row, so a cached artifact served on a later day hands `_todayNum` a record
  /// that still claims to be today — and yesterday's strain and nap minutes land
  /// inside tonight's `need_sec`. That is the exact imputation the stamp exists
  /// to prevent (§3.3), arriving through the cache instead of through `_lastNum`.
  ///
  /// Every current `_runCrossDay` call site refreshes the artifact immediately
  /// beforehand, so the stale read is not reachable today. That is an unenforced
  /// ordering coincidence and not something to rely on: one new caller, or one
  /// early return inside `_refreshBaselines`, makes it live and silent.
  ///
  /// An artifact with no `built_for_day` (written before this field existed)
  /// cannot be SHOWN to be fresh, so it is rebuilt rather than assumed fresh.
  static bool crossDayArtifactUsableToday(Object? decoded, String today) {
    if (decoded is! Map) return false;
    if (decoded['days'] is! List) return false;
    // The artifact stamps `algo_version` and this gate used to ignore it, so a
    // version bump that CHANGES THE ROW SHAPE (a new per-day field, e.g.
    // `hourly_hr`) was served from the pre-bump artifact for the rest of the
    // day — the new cross-day family silently saw nothing on the very pass the
    // bump existed to trigger. A shape the current code did not write is not
    // reusable, whatever day it was built for.
    if ((decoded['algo_version'] as num?)?.toInt() != kAlgoVersion) {
      return false;
    }
    final builtFor = decoded['built_for_day'];
    return builtFor is String && builtFor.isNotEmpty && builtFor == today;
  }

  Future<String> rebuildCrossDay(Profile profile) {
    final stopGen = DeriveStop.generation;
    return _withRunLock('busy', () async {
      await _refreshCrossDayInputArtifact();
      DeriveStop.check(stopGen);
      return _runCrossDay(profile);
    });
  }

  Future<String> _runCrossDay(Profile profile) async {
    final stopGen = DeriveStop.generation;
    try {
      final days = await _crossDayInputDays();
      final usableDays = days.length;
      // Replay only corrected days. Decode their compact payloads off the UI
      // isolate, preserving raw-retention independence without a main-thread
      // loop over 90 large bundles on every sync.
      final now = DateTime.now();
      final firstDate = dayLabelOf(
        DateTime(now.year, now.month, now.day - _crossDayWindow + 1),
      );
      final today = LocalDb.localDayLabelNow();
      final dates = (await LocalDb.napCorrectionDays())
          .where((d) => d.compareTo(firstDate) >= 0 && d.compareTo(today) <= 0)
          .toList();
      final rows = [for (final date in dates) await LocalDb.dayResult(date)];
      DeriveStop.check(stopGen);
      final blocks = await _runIsolateCancellable(
        () {
          return <String, Map<String, dynamic>?>{
            for (final row in rows)
              if (row != null)
                row['day_id'] as String: switch (_decodeBundle(
                  row['payload_json'],
                )?['naps']) {
                  final Map n => n.cast<String, dynamic>(),
                  _ => null,
                },
          };
        },
        _crossDayTimeout,
        label: 'nap-corrections',
      );
      DeriveStop.check(stopGen);
      final known = {for (final d in days) d['date']};
      for (final date in dates) {
        final naps = await NapLedger.read(date, blocks[date]);
        if (known.contains(date)) {
          days.firstWhere((d) => d['date'] == date)['nap_min'] =
              naps['nap_min'];
          continue;
        }
        if (naps['nap_min'] is! num) continue;
        final at = DateTime.tryParse(date), now = DateTime.now();
        if (at == null ||
            at.isBefore(
              DateTime(now.year, now.month, now.day - _crossDayWindow + 1),
            ) ||
            date.compareTo(LocalDb.localDayLabelNow()) > 0)
          continue;
        // A report credits a nap, without inventing overnight measurements or
        // counting this extra record toward the minimum usable-day gate.
        days.add({
          'date': date,
          'nap_min': naps['nap_min'],
          if (date == LocalDb.localDayLabelNow()) 'is_today': true,
          'unsettled': true,
        });
      }
      days.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      if (usableDays < 3) {
        _log('crossday: only ${days.length} usable day(s) — skip');
        DeriveStop.check(stopGen);
        await LocalDb.putBaseline(
          'crossday_status',
          jsonEncode({'kind': 'needs_history', 'days': days.length}),
        );
        return 'needs_history';
      }
      final profileMap = profile.toMap();
      // Her own logged cycle starts. Read on the DB-owning isolate (sqflite),
      // passed in as plain strings so the bundle stays pure. Only `start`
      // markers — the other kinds are not what a cycle is counted from.
      final cycleStarts = <String>[
        for (final r in await LocalDb.cycleLogs())
          if (r['kind'] == 'start' && r['date'] is String) r['date'] as String,
      ];
      // TS-11's grouping key. Read here (sqflite is main-isolate only) and
      // handed in as plain strings so the bundle stays pure.
      final sessionTypes = await _sessionTypesByDate(days);
      // Encode INSIDE the isolate too — a real ~3.5-4.7s main-isolate hang was
      // caught in production (Crashlytics jank_watchdog, correlated with a
      // heavy derive pass) coming from jsonEncode-ing this bundle back on the
      // main isolate after Isolate.run returned it. Returning the already-
      // encoded string avoids both the main-isolate encode cost AND transfers
      // a flat string across the isolate boundary instead of a large nested Map.
      // Stamped so the READER can fail closed. Without these the bundle was
      // indistinguishable from a current one: after a version bump — or on any
      // path that leaves the stored artifact untouched (the `< 3 days` return
      // above, or the catch below) — VO₂max, fitness age, sleep need, strain
      // target, glass-box readiness and the illness flags all kept serving the
      // PREVIOUS version's answers with nothing on screen to say so. Same
      // defect as `crossDayArtifactUsableToday` guards on the INPUT artifact,
      // one layer up on the output.
      final builtForDay = LocalDb.localDayLabelNow();
      final builtAtEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final crossDayContext = DayClock.snapshot();
      DeriveStop.check(stopGen);
      final (bundleJson, dropped, needSec) = await _runIsolateCancellable(
        () {
          DayClock.restore(crossDayContext);
          final bundle =
              buildCrossDayBundle(
                  days,
                  profileMap,
                  cycleStartDates: cycleStarts,
                  sessionTypesByDate: sessionTypes,
                )
                ..['algo_version'] = kAlgoVersion
                ..['built_for_day'] = builtForDay
                ..['built_at_epoch'] = builtAtEpoch;
          // Encode-safety BEFORE jsonEncode, never a try/catch around it: one
          // non-finite leaf must cost that leaf, not the whole artifact.
          final paths = <String>[];
          final safe = sanitizeForJson(bundle, paths) as Map<String, dynamic>;
          if (paths.isNotEmpty) safe['encode_dropped_fields'] = paths;
          final coach = safe['sleep_coach'];
          final needEnv = coach is Map ? coach['need'] : null;
          final needVal = needEnv is Map ? needEnv['value'] : null;
          final need = needVal is Map ? needVal['need_sec'] as num? : null;
          return (jsonEncode(safe), paths, need?.toDouble());
        },
        _crossDayTimeout,
        label: 'crossday',
      );
      DeriveStop.check(stopGen);
      await LocalDb.putBaseline('crossday', bundleJson);
      // B88-04: keep each day's computed need as that day's series point, so
      // the Home sleep bar can divide last night's sleep by the need that
      // applied to last night, not by tonight's. Written only when present.
      if (needSec != null) {
        await LocalDb.putMetricSeriesValue(
          builtForDay,
          'sleep_need_min',
          (needSec / 60).roundToDouble(),
        );
      }
      if (dropped.isNotEmpty) {
        // Loud, not debug-only: a dropped field is a metric the user will see
        // as absent, and the reason lives here and nowhere else.
        debugPrint(
          '[derive] crossday: ${dropped.length} field(s) were not '
          'JSON-encodable and were stored as absent: ${dropped.join(", ")}',
        );
      }
      _log('crossday: stored over ${days.length} day(s)');
      DeriveStop.check(stopGen);
      await LocalDb.putBaseline(
        'crossday_status',
        jsonEncode({'kind': 'ready', 'days': days.length}),
      );
      return 'ready';
    } catch (e, st) {
      if (e is DeriveCancelled || DeriveStop.generation != stopGen) rethrow;
      // NOT a debug line. A failure here means the stored bundle is now STALE
      // — the reader's version/day stamp will reject it and the whole
      // cross-day family goes absent — so it has to be visible in a release
      // build, with the stack, or the cause is unrecoverable after the fact.
      debugPrint(
        '[derive] crossday BUNDLE DROPPED — the stored artifact is '
        'now stale and every cross-day metric will read absent: $e\n$st',
      );
      _log('crossday FAILED/skipped: $e');
      await LocalDb.putBaseline(
        'crossday_status',
        jsonEncode({'kind': 'failed'}),
      );
      return 'failed';
    }
  }

  /// Every FINISHED saved session, grouped by the local day it started on
  /// (TS-11's `sessionTypesByDate`).
  ///
  /// A live session is excluded — it has no end and no next morning yet, and
  /// including it would make today look like a single-session day that it may
  /// not turn out to be.
  ///
  /// The key is the CALENDAR-local day label, the same alphabet the day rows
  /// use. It is not the wake-to-wake physiological boundary, so a session
  /// started between midnight and wake is filed under the calendar day it
  /// began rather than the physiological day it ends inside. That costs at most
  /// the attribution of a 1 a.m. workout; the analytics drops multi-session
  /// days and refuses under ten mornings per type either way.
  static Future<Map<String, List<String>>> _sessionTypesByDate(
    List<Map<String, dynamic>> days,
  ) async {
    if (days.isEmpty) return const {};
    final first = days.first['date'];
    if (first is! String || first.isEmpty) return const {};
    final fromSec = _localDayLabelToSec(first);
    final toSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = <String, List<String>>{};
    for (final r in await LocalDb.sessionsInRange(fromSec, toSec)) {
      if (r['status'] == 'live') continue;
      final start = (r['start_ts'] as num?)?.toInt();
      final type = r['type']?.toString();
      if (start == null || type == null || type.isEmpty) continue;
      out.putIfAbsent(dayLabelAtSec(start), () => <String>[]).add(type);
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _crossDayInputDays() async {
    final artifact = await LocalDb.baseline('crossday_input');
    final raw = artifact?['payload_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        // Day-gated, NOT just well-formed. The rows carry `is_today`, which is a
        // fact about the day the artifact was BUILT on; serving them on a later
        // day makes `_todayNum` read yesterday's strain and nap minutes as
        // today's (§3.3). See [crossDayArtifactUsableToday].
        if (crossDayArtifactUsableToday(decoded, LocalDb.localDayLabelNow())) {
          final rows = (decoded as Map)['days'] as List;
          return [
            for (final row in rows)
              if (row is Map) row.cast<String, dynamic>(),
          ];
        }
      } catch (_) {
        // Fall through to rebuild from day_result.
      }
    }
    return _refreshCrossDayInputArtifact();
  }

  Future<List<Map<String, dynamic>>> _refreshCrossDayInputArtifact() async {
    // The DB read itself must stay on the main isolate (sqflite), but
    // decoding up to _crossDayWindow (90) full day payloads + re-encoding
    // them was previously ALL synchronous main-isolate work with zero
    // offloading — this is the confirmed source of the ~3.5-4.7s production
    // hang (Crashlytics jank_watchdog), since _refreshBaselines calls this
    // unconditionally on every heavy pass. _decodeBundle/_crossDayRecord are
    // both static, so this whole transform+encode step is isolate-safe.
    final rows = await LocalDb.recentDayResults(_crossDayWindow);
    final today = LocalDb.localDayLabelNow();
    // B88-11: another vendor's imported days are not this band's measurements;
    // tagged here so every cross-day consumer drops them.
    final imported = await LocalDb.importedDates();
    final (days, json) = await _runIsolateCancellable(
      () {
        final days = <Map<String, dynamic>>[];
        for (final row in rows.reversed) {
          final payload = _decodeBundle(row['payload_json']);
          if (payload == null) continue;
          if (payload['skipped'] == true) continue;
          final rec = _crossDayRecord(row, payload);
          if (rec == null) continue;
          // Today's own row updates on every derive pass while the night is
          // still syncing/settling — feeding that partial reading into the
          // illness/anomaly CUSUM can fire a false "possible illness onset" on
          // data that's really just a truncated/mid-drain night. Only exclude
          // TODAY specifically; older days already had their 48h to settle.
          //
          // FLAG it rather than DROP it: `days` is the single input list for the
          // whole cross-day bundle, so dropping today also silently removed it
          // from readiness/glass-box, the resting-HR trend-shift CUSUM, load,
          // sleep debt and `recent` (whose last row dates every notification).
          // buildCrossDayBundle nulls only the alert inputs for a flagged day.
          if (row['day_id'] == today && (row['finalized'] as num?) != 1) {
            rec['unsettled'] = true;
          }
          // Explicit identity for TODAY-scoped reads. `unsettled` cannot serve
          // this purpose — it is only set while today is unfinalized. Without a
          // flag, a today-scoped consumer can only take the LAST record
          // positionally, which on a day with no derived row is YESTERDAY's.
          if (row['day_id'] == today) rec['is_today'] = true;
          if (imported.contains(row['day_id'])) rec['imported'] = true;
          days.add(rec);
        }
        // `built_for_day` is what makes the `is_today` stamps inside `days`
        // interpretable later. Without it the envelope carries day-relative facts
        // with no day attached, and any reader has to assume freshness.
        return (
          days,
          jsonEncode({
            'algo_version': kAlgoVersion,
            'built_for_day': today,
            'days': days,
          }),
        );
      },
      _crossDayTimeout,
      label: 'crossday-input',
    );
    await LocalDb.putBaseline('crossday_input', json);
    return days;
  }

  // ── notifications generator ─────────────────────────────────────────────────

  Future<void> _runNotifications() async {
    try {
      final cdRow = await LocalDb.baseline('crossday');
      final cd = _decodeBundle(cdRow?['payload_json']);
      if (cd == null) return;
      String? date;
      var lastUnsettled = false;
      final recent = cd['recent'];
      if (recent is List && recent.isNotEmpty) {
        final last = recent.last;
        if (last is Map) {
          date = last['date'] as String?;
          lastUnsettled = last['unsettled'] == true;
        }
      }
      final illness = cd['illness'] is Map ? cd['illness'] as Map : null;
      final anomaly = cd['anomaly'] is Map ? cd['anomaly'] as Map : null;
      final temp = cd['temp_illness'] is Map ? cd['temp_illness'] as Map : null;
      date ??=
          (illness?['date'] ?? anomaly?['date'] ?? temp?['date']) as String?;
      // ANCHORED TO THE DAY THIS IS RUNNING ON, not to the newest DERIVED day.
      //
      // Every date in here is the newest day the rollup happened to see, which
      // is not today whenever the newest data is old: import a back-catalogue
      // (finalizeImport runs this straight after) or bump kAlgoVersion after a
      // week off the wrist, and a critical, quiet-hours-overriding "Possible
      // illness onset" goes out about nights from last November — in the
      // present tense, with the irregular-rhythm copy saying "today".
      //
      // Yesterday still counts: before the first sync of the day (and just
      // after midnight) the newest derived night IS yesterday's, and that
      // finding is current. Anything older is history, and history does not
      // interrupt.
      final today = LocalDb.localDayLabelNow();
      final calendar = DateTime.parse(today);
      final yesterday = dayLabelOf(
        DateTime(calendar.year, calendar.month, calendar.day - 1),
      );
      if (date == null || (date != today && date != yesterday)) return;
      // ONE exception per day, not one per finding.
      //
      // These six signals are correlated by construction — an illness flag, an
      // overnight anomaly and an elevated skin temperature are usually the same
      // morning saying the same thing — and they used to fire as six separate
      // notifications, two of them on the recovery channel. Under the
      // three-class rule (alarm · exception · lookback) the day's findings are
      // collected here and presented once, aggregated, so the user gets one
      // buzz and the whole picture instead of six buzzes and a third of it.
      //
      // `medical` marks the DETECTION-class findings — the ones the design
      // sanctions interrupting for. It only affects the dedupe key (below),
      // never the wording.
      // The SENTENCES live in findings.dart, with the log that reads the same
      // six. They were inline here, which is exactly how a second surface for
      // the same detector ends up quietly differently worded.
      final findings = <Finding>[];
      if (illness != null && illness['state'] == 'red') {
        findings.add(Finding(FindingKind.illness, date));
      }
      if (anomaly != null && anomaly['flagged'] == true) {
        findings.add(Finding(FindingKind.anomaly, date));
      }
      if (temp != null && temp['flag'] == 'elevated') {
        findings.add(Finding(FindingKind.tempElevated, date));
      }
      // The 24/7 irregular-rhythm screen is a details-only note (B88 C1): a
      // sparse wrist-beat heuristic is not AF detection, so it never pushes.
      // LOW READINESS from the HEADLINE composite the ring shows (B88-11),
      // never the deprecated glass-box percentile. The composite already
      // withholds itself while the overnight is incomplete (its own input and
      // weight gates), so it is not additionally gated on `unsettled`: a day
      // only finalizes 48 h later, which would suppress every same-morning
      // finding.
      final score = await LocalDb.metricValueOn(date, 'readiness');
      if (score != null && score < kLowReadiness) {
        findings.add(Finding(FindingKind.lowReadiness, date));
      }

      // "Something changed" — online CUSUM on the recent resting-HR series.
      // Only when the shift lands on the day this notification is STAMPED with
      // (a fresh change, not old history we'd re-announce every pass).
      //
      // The dates travel with the values. `rhrSeries` is compacted — days with
      // no nocturnal RHR are skipped, which is most days for some users — so
      // `index == length - 1` meant "the most recent day that HAPPENED to have
      // an rhr". With a few null days in between, a week-old shift satisfied it
      // and went out at critical priority under today's date.
      //
      // `recent[].rhr` is written WITHOUT the `settled()` guard on purpose —
      // the guard's comment names `recent` and "RHR trend" as things an
      // unsettled day still feeds, and the trend chart is right to show it.
      // A critical-priority ALERT is not: a night that is only half drained
      // reads several bpm high, fires "your resting HR trend shifted", and then
      // corrects an hour later with the day's dedupe key already claimed. So
      // the trend keeps the raw value and this one consumer stands down until
      // the day settles.
      final rhrSeries = <double>[];
      final rhrDates = <String?>[];
      if (recent is List) {
        for (final r in recent) {
          if (r is Map && r['rhr'] is num) {
            // B88-11: a wear gap of more than 7 days restarts the evidence, so
            // a shift is never "detected" against a pre-gap baseline.
            final d = r['date'] as String?;
            final prev = rhrDates.isEmpty ? null : rhrDates.last;
            if (d != null && prev != null) {
              final gap = DateTime.parse(d).difference(DateTime.parse(prev));
              if (gap.inDays > 7) {
                rhrSeries.clear();
                rhrDates.clear();
              }
            }
            rhrSeries.add((r['rhr'] as num).toDouble());
            rhrDates.add(d);
          }
        }
      }
      if (!lastUnsettled && rhrSeries.length >= 10) {
        final dets = ana.cusumChangePoints(rhrSeries, h: 5.0);
        if (dets.isNotEmpty && rhrDates[dets.last.index] == date) {
          findings.add(
            Finding(FindingKind.rhrShift, date, risen: dets.last.direction > 0),
          );
        }
      }

      // B88-12 (C8): a kind the user switched off never reaches the
      // notification; the in-app findings log still lists it.
      final muted = (await NotificationPrefs.load()).mutedFindings;
      findings.removeWhere((f) => muted.contains(f.kind.name));
      if (findings.isEmpty) return;
      final one = findings.length == 1;
      // The key carries the day's HIGHEST severity class, not just the day.
      //
      // With a bare '$date:exception' the first pass of the day claimed the
      // slot whatever it found, so a day that opened with nothing but "low
      // readiness" and then turned an illness flag RED in the evening
      // discarded the illness flag — the one class of notification the design
      // does sanction, suppressed by a low-priority sibling of the same day.
      // Keyed this way an ESCALATION still gets through exactly once, while a
      // re-derive that finds the same class again (or merely adds another
      // finding of a class already announced) stays silent.
      // The other direction needs saying too: a day that opens RED and then
      // DE-escalates (the illness flag clears by evening, "low readiness"
      // remains) used to buzz a second time under the still-unclaimed plain
      // key, about a finding the morning's aggregate already carried. So a
      // presented medical exception burns the day's plain slot as well —
      // only on a real present, or a medical one lost to quiet hours would
      // take the plain one down with it.
      final medical = findings.any((f) => f.medical);
      final fired = await NotificationCenter.instance.emit(
        NotificationEvent(
          dedupeKey: medical ? '$date:exception:medical' : '$date:exception',
          category: NotifCategory.health,
          // B88-11 / D4: every health finding respects quiet hours.
          priority: NotifPriority.normal,
          title: one
              ? findings.first.title
              : '${findings.length} things to look at',
          body: one
              ? findings.first.detail
              : findings.map((f) => '• ${f.title} — ${f.detail}').join('\n'),
          date: date,
          route: '/heart',
        ),
      );
      if (medical && fired) {
        await const FiredKeyStore().recordFired('$date:exception');
      }
    } catch (e) {
      _log('notifications FAILED/skipped: $e');
    }
  }

  /// Decode a stored day bundle, normalizing the compact curve format back to
  /// plain [{t,v}] lists.
  ///
  /// The normalization is LOAD-BEARING on the re-derive path, not just hygiene:
  /// `_deriveOneDay` reads the previous row through here and merges its series
  /// into the fresh bundle. Without normalizing, an encoded `prev` would be
  /// merged beside newly-computed legacy lists and the day would carry two
  /// different shapes for the same curve.
  static Map<String, dynamic>? _decodeBundle(Object? json) =>
      SeriesCodec.decodePayloadJson(json);

  /// Build the cross-day record from a day_result row + its payload bundle.
  static Map<String, dynamic>? _crossDayRecord(
    Map<String, dynamic> row,
    Map<String, dynamic> payload,
  ) {
    final date = row['day_id'] as String?;
    if (date == null || date.isEmpty) return null;
    final scalars =
        (payload['scalars'] as Map?)?.cast<String, dynamic>() ?? const {};
    num? sc(String k) => scalars[k] is num ? scalars[k] as num : null;
    num? col(String k) => row[k] is num ? row[k] as num : null;

    // Safe map cast: a metric envelope's `value` is the string '—' when the
    // metric is ABSENT (e.g. a no-sleep day), so a blind `as Map?` throws. Only
    // treat it as a map when it really is one.
    Map<String, dynamic>? asMap(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : null;

    final sleep = asMap(payload['sleep']);
    final win = asMap(sleep?['window']);
    final winVal = asMap(win?['value']);
    final acct = asMap(sleep?['accounting']);
    final acctVal = asMap(acct?['value']);
    final series = asMap(payload['series']);

    final onsetMs = (winVal?['onset_ms'] as num?)?.toDouble();
    final offsetMs = (winVal?['offset_ms'] as num?)?.toDouble();
    final tstSec = (acctVal?['tst_sec'] as num?)?.toDouble();
    final inBedSec = (acctVal?['in_bed_sec'] as num?)?.toDouble();
    final observedSec = (acctVal?['observed_in_bed_sec'] as num?)?.toDouble();

    return {
      'date': date,
      'rhr': col('rhr') ?? sc('rhr'),
      'rmssd': col('rmssd') ?? sc('rmssd'),
      'readiness': col('readiness') ?? sc('readiness'),
      'resp_rate': sc('resp_rate'),
      'skin_temp_z': sc('skin_temp_z'),
      // B88-01: raw nightly mean + family so the cross-day detectors can refuse
      // unverified/imported temperature and read the quantity they require.
      'skin_temp_adc': sc('skin_temp_adc'),
      'device_family': payload['device_family'],
      'trimp': sc('trimp'),
      // B88-02: load uses net TRIMP on days the band recorded ≥16 h.
      'trimp_net': sc('trimp_net'),
      'worn_min': sc('worn_min'),
      // Headline 0–21 strain, daily steps, nap minutes — feed Sleep/Strain Coach
      // + VO₂max/Fitness Age in the cross-day rollup.
      'strain': sc('strain'),
      'steps': sc('steps'),
      'nap_min': sc('nap_min'),
      'efficiency': sc('efficiency'),
      'onset_sec': onsetMs == null ? null : (onsetMs / 1000).round(),
      'wake_sec': offsetMs == null ? null : (offsetMs / 1000).round(),
      'tst_min': tstSec == null ? null : (tstSec / 60).round(),
      // Fraction of the night we actually watched — wall-clock in-bed minus the
      // seconds nobody observed, over in-bed. TS-11 drops a morning whose night
      // is under half observed: a resting HR from two hours of contact is not a
      // morning, and it would otherwise be attributed to whatever session the
      // day before happened to hold.
      // Unknown stays NULL, never 0: a night whose segmentation did not report
      // what it watched is not a night we watched none of, and 0 would read as
      // a confident "no coverage".
      'sleep_coverage':
          (inBedSec == null || inBedSec <= 0 || observedSec == null)
          ? null
          : observedSec / inBedSec,
      'hypnogram': series?['hypnogram'],
      'day_zone': payload['day_zone'],
      'sleep_spans_zone_change': payload['sleep_spans_zone_change'],
      'sleep_onset_local_min': payload['sleep_onset_local_min'],
      'sleep_wake_local_min': payload['sleep_wake_local_min'],
      // 24 local-hour means of this day's HR curve — the ONLY intraday series
      // that survives long enough to support cross-day circadian analysis.
      // `day_result` is never pruned; the 1 Hz substrate is gone after 3 days,
      // so accelerometry (the textbook ENMO input) simply does not exist far
      // enough back. `circadianNonparametric` documents HR as an accepted
      // input alongside activity. 24 numbers a day, so the artifact stays small.
      'hourly_hr': hourlyHrProfile(series?['hr_curve']),
    };
  }

  /// Mean HR per LOCAL hour-of-day (24 entries, `null` where the hour is not
  /// covered) from a stored `series.hr_curve` (`[{t: epochSec, v: bpm}]`).
  ///
  /// An hour counts as covered only with [minMinutes] real minute-samples in
  /// it, so a bin is always a mean over genuine readings — never an average of
  /// one stray second, and never an imputed value. Gaps stay null and the
  /// consumer excludes the day; nothing is filled in.
  static List<double?> hourlyHrProfile(Object? hrCurve, {int minMinutes = 5}) {
    final sums = List<double>.filled(24, 0);
    final counts = List<int>.filled(24, 0);
    if (hrCurve is List) {
      for (final e in hrCurve) {
        if (e is! Map) continue;
        final t = (e['t'] as num?)?.toInt();
        final v = (e['v'] as num?)?.toDouble();
        if (t == null || v == null || v <= 0) continue;
        // LOCAL hour. The day model is local-midnight-to-midnight, so the UTC
        // hour would smear a user's evening into the next bin (and, for a
        // non-integral-offset zone, into the wrong one entirely).
        final h = DateTime.fromMillisecondsSinceEpoch(t * 1000).hour;
        if (h < 0 || h > 23) continue;
        sums[h] += v;
        counts[h] += 1;
      }
    }
    return [
      for (var h = 0; h < 24; h++)
        counts[h] >= minMinutes ? sums[h] / counts[h] : null,
    ];
  }

  /// Refresh the persisted rolling-baseline artifact + signature caches.
  ///
  /// Rebuilds from the de-duplicated `metric_series` store (see
  /// [_BaselineHistoryCache.load]) rather than persisting the in-memory cache
  /// the sweep mutated via [_BaselineHistoryCache.appendScalars] — that list is
  /// correct for intra-sweep freshness but is append-only with no day identity,
  /// so persisting it let repeated same-day re-derives stack duplicate copies of
  /// today into the window (the blank-readiness root cause). The read path
  /// ([_BaselineHistoryCache.load]) no longer trusts this artifact for history,
  /// but it still backs the cheap `signature` rescan gate, so keep it fresh.
  Future<void> _refreshBaselines() async {
    final history = await _BaselineHistoryCache.load();
    final artifact = history.toArtifactJson();
    final rolling = ((artifact['rolling'] as Map?) ?? const {})
        .cast<String, dynamic>();
    await LocalDb.putBaseline('rolling_artifact', jsonEncode(artifact));
    await LocalDb.putBaseline('rolling', jsonEncode(rolling));
    await _refreshCrossDayInputArtifact();
  }

  // ── raw pruning (raw-first invariant) ──────────────────────────────────────

  /// Longest the raw-first hold below may keep substrate past
  /// [rawRetentionDays] for a day that still hasn't produced a complete result.
  ///
  /// The hold has to be bounded or it is not a hold, it is an off switch. A
  /// `partial` day is DELIBERATELY never finalized by age (see
  /// `_derivePreparedDay` — a headline-only row must keep its chance to be
  /// filled in), and `dayResultIds` excludes both `partial` and `skipped`, so a
  /// day whose second half fails every single time never becomes "derived" and
  /// never becomes finalized either. One such day used to latch pruning off for
  /// the whole install, forever, at ~12 MB/day.
  static const int _maxRawHoldDays = 14;

  /// The `rec_ts` below which decoded substrate may be deleted, or null when
  /// nothing may be. PURE — the decision the raw prune is, separated from the
  /// two DB calls that surround it. See [_pruneOldDecoded] for the contract.
  @visibleForTesting
  static int? rawPruneCutoffSec({
    required int dataNowSec,
    required List<String> rawDayIds,
    required Set<String> derivedDayIds,
  }) {
    final cutoffSec = dataNowSec - rawRetentionDays * 86400;
    if (cutoffSec <= 0) return null;
    final pending = rawDayIds.where((d) => !derivedDayIds.contains(d)).toList()
      ..sort();
    if (pending.isEmpty) return cutoffSec;
    // Hold at the START of the oldest day still owed a result — its own rows
    // survive, everything before it goes — floored so a permanently stuck day
    // cannot hold the whole install (see [_maxRawHoldDays]).
    final barrier = math.max(
      _localDayLabelToSec(pending.first),
      dataNowSec - _maxRawHoldDays * 86400,
    );
    return barrier < cutoffSec ? barrier : cutoffSec;
  }

  /// Prune raw older than [rawRetentionDays] BEHIND THE DATA EDGE. Retention is
  /// measured against the last record timestamp we actually drained
  /// ([dataNowSec]), never the wall clock, and rows are deleted by their record
  /// time (`rec_ts`), never receive time (`captured_at`) — a multi-day flash
  /// backfill received in one sync must not be pruned just because it landed
  /// "now".
  ///
  /// RAW-FIRST, DAY-SCOPED. A day in [rawDayIds] with no complete result at the
  /// current algo version pulls the cutoff back to ITS OWN start instead of
  /// aborting the whole prune — the old all-or-nothing guard meant a single
  /// stuck day kept every older day's substrate too. Bounded by
  /// [_maxRawHoldDays] so a permanently-stuck day cannot wedge it.
  ///
  /// [rawDayIds] must be every day that still HAS substrate (`scope.rawDays`),
  /// not the days this pass targeted: the day at risk is precisely the one that
  /// fell out of the scope while still un-derived.
  ///
  /// WHY THIS CANNOT RACE A COMPUTATION THAT STILL NEEDS THE ROWS:
  ///   * Both call sites are inside `run()`, which holds the process-wide
  ///     `_running` latch across its entire body — no other derive, restage,
  ///     rescan or import pass can be reading substrate while this runs.
  ///   * Within this run it is reached only after `runWithConcurrency` has
  ///     awaited every day's `processDay` (prepare + compute + persist) and
  ///     after the cross-day rollup, so nothing in flight still holds a claim.
  ///   * It does not move the retention window — that is still
  ///     `rawRetentionDays` behind the data edge, exactly as documented. This
  ///     change only makes the documented window actually apply. Anything that
  ///     must outlive it has to be PERSISTED into `day_result` when the day is
  ///     derived rather than re-read from `decoded_onehz` on demand — which is
  ///     why a workout's average HR is written into the bundle (it was once
  ///     re-derived lazily and vanished the moment its substrate aged out).
  Future<void> _pruneOldDecoded(List<String> rawDayIds, int dataNowSec) async {
    final derivedIds = await LocalDb.dayResultIds(kAlgoVersion);
    final cutoffSec = rawPruneCutoffSec(
      dataNowSec: dataNowSec,
      rawDayIds: rawDayIds,
      derivedDayIds: derivedIds,
    );
    if (cutoffSec == null) return;
    final deleted = await LocalDb.pruneDecodedBeforeRecTs(cutoffSec);
    if (deleted > 0) {
      _log('pruned $deleted decoded rows with rec_ts < $cutoffSec');
    }
    // Superseded generations of the recomputable per-day intermediates. Runs
    // here rather than inside the decoded prune so it stays off the path to a
    // durable commit.
    final stale = await LocalDb.pruneSupersededIntermediates();
    if (stale > 0) {
      _log('pruned $stale superseded intermediate rows');
    }
  }

  /// Storage housekeeping that must run on EVERY derive.
  ///
  /// Deliberately NOT inside [_pruneOldDecoded]: both of that method's call
  /// sites sit behind `if (scope.fullHistory)`, and ordinary light/heavy
  /// derives run with `fullHistory: false`. Putting the back-catalogue rewrite
  /// there made it resumable but effectively unreachable — a normal install
  /// would have converted nothing.
  ///
  /// CALLED FROM THE `finally` OF EVERY ENTRY PATH, and it swallows its own
  /// errors, for two reasons that were both live:
  ///
  ///   • Reach. Called from the body, it sat below `if (dataNowSec <= 0)
  ///     return 0` and below two other early returns — so the install that most
  ///     needs it, one restored from a backup with years of derived history and
  ///     no decoded rows at all (they are capped at `rawRetentionDays`, so a
  ///     backup carries almost none), converted nothing, ever. runDays and
  ///     rescanRecent never reached it at all.
  ///   • Blast radius. Called unguarded from the body, a throw — SQLITE_BUSY
  ///     from the other derivation isolate, a full disk — skipped the raw prune
  ///     that enforces `rawRetentionDays`, skipped the timezone re-baseline, and
  ///     landed in the run-wide catch, so a derive that had actually completed
  ///     every day reported 0 back to `reanalyzeAll`. This work is a storage
  ///     optimization; nothing it does may change what the derive returns.
  ///
  /// Bounded and resumable, so running it on every pass costs one small batch.
  /// Off the path to a durable commit, and never inside a migration: `onUpgrade`
  /// runs under iOS's CPU watchdog (invariant 11).
  Future<void> _runStorageHousekeeping() async {
    try {
      final reencoded = await LocalDb.reencodeLegacyDayResults();
      if (reencoded > 0) {
        _log('re-encoded $reencoded legacy day bundles');
      }
    } catch (e) {
      _log('storage housekeeping skipped: $e');
    }
  }

  /// The wake-minute series WITH its bucket keys (epoch-seconds ~/ 60), so a
  /// per-minute companion series (the measured cadence) can be aligned to the
  /// same minutes instead of guessed from array position.
  static ({List<int> keys, List<double> hr}) _perMinuteMeanWake(
    Substrate s,
    int sleepOnsetSec,
    int sleepOffsetSec,
  ) {
    final buckets = <int, List<double>>{};
    for (var i = 0; i < s.hr.length && i < s.tsSec.length; i++) {
      if (s.hr[i] <= 0) continue;
      final t = s.tsSec[i];
      if (sleepOffsetSec > sleepOnsetSec &&
          t >= sleepOnsetSec &&
          t < sleepOffsetSec) {
        continue;
      }
      (buckets[t ~/ 60] ??= []).add(s.hr[i].toDouble());
    }
    final keys = buckets.keys.toList()..sort();
    return (keys: keys, hr: [for (final k in keys) _meanWake(buckets[k]!)!]);
  }

  /// Whether `daySub` has AT LEAST ONE real HR sample (`hr > 0`) inside
  /// `[fromSec, toSec)` — the gate for the workout-gap credit in
  /// [applyDayActivity]. Same "real sample" test as [_perMinuteMeanWake]'s own
  /// bucketing, so "covered" here means exactly what would have priced a
  /// minute there.
  static bool _hasHrCoverage(Substrate s, int fromSec, int toSec) {
    for (var i = 0; i < s.hr.length && i < s.tsSec.length; i++) {
      if (s.hr[i] <= 0) continue;
      final t = s.tsSec[i];
      if (t >= fromSec && t < toSec) return true;
    }
    return false;
  }

  static Map<String, int> _wakeZoneMinutes(
    Substrate s,
    int sleepOnsetSec,
    int sleepOffsetSec,
    double hrMax, {
    ana.HeartRateZoneSet? zoneSet,
  }) {
    final samples = <ana.HrSample>[];
    final n = math.min(s.tsSec.length, s.hr.length);
    for (var i = 0; i < n; i++) {
      final ts = s.tsSec[i];
      if (sleepOnsetSec > 0 &&
          sleepOffsetSec > sleepOnsetSec &&
          ts >= sleepOnsetSec &&
          ts < sleepOffsetSec) {
        continue;
      }
      samples.add(ana.HrSample(ts * 1000.0, s.hr[i].toDouble()));
    }
    final bands = zoneSet ?? ana.HeartRateZones.zonesFromMaxHr(hrMax);
    // Null = the stream has no cadence `sampleCadenceSeconds` will vouch for.
    // An empty map is already this function's "no zones" answer everywhere it
    // is read; a zero-filled one would claim the day was measured and spent at
    // rest. See `HeartRateZones.timeInZone`.
    return ana.HeartRateZones.timeInZone(
          samples,
          bands,
        )?.toRoundedMinuteMap() ??
        const {};
  }

  /// ONE HR-flex pass, returning the day's active, basal and total figures
  /// TOGETHER so they cannot disagree. THE canonical day calorie computation —
  /// every other day-level site mirrors this one, never re-derives it.
  ///
  /// [wakeHrPerMin] is the per-minute mean HR over the WAKE span only, and
  /// [dayMinutes] is how many minutes of the whole calendar day the substrate
  /// actually covers. That split is deliberate and is the whole semantic:
  ///
  ///   * active = Keytel surplus over the wake minutes. Sleep is not exercise.
  ///     Passing the whole-day series here bills the night as active energy:
  ///     `dailyEnergy`'s flex gate is 0.50*HRmax = 104 - 0.35*age bpm, which is
  ///     79.5 bpm at age 70, so an older sleeper whose nocturnal HR sits above
  ///     it gains thousands of fabricated active kcal per night.
  ///   * basal = Mifflin BMR pro-rated over [dayMinutes] — the WHOLE day,
  ///     sleep included, because basal metabolism does not stop overnight.
  ///   * total = basal + active, i.e. TDEE.
  ///
  /// This replaces a derivation-local Keytel sum (`_keytelCaloriesWake`) that
  /// billed the full Keytel rate on every active minute while `calories_total`
  /// came from a SECOND, separately-gated `ana.Calories.dailyEnergy` call whose
  /// active component nets out the basal minute already counted inside the
  /// total. The same minute was paid for twice, so `calories` read high by
  /// basalPerMin x active-minutes and the basal the Health export derives as
  /// `total - active` read low by the same amount. Active and total now come
  /// from a single call, and `total - active == basal` holds by construction.
  ///
  /// Returns null when the profile lacks an anchor Keytel actually reads
  /// ([Profile.hasCalorieAnchors]), when it carries no HEIGHT, or when no wake
  /// heart rate was recorded — absent beats fabricated, and "no HR at all" is
  /// not the same claim as "this day burned exactly your BMR".
  ///
  /// HEIGHT IS REQUIRED even though Keytel does not read it, and all three
  /// figures go absent without it. That is not the shape I wanted: height only
  /// enters through the Mifflin basal floor, so in principle the ACTIVE figure
  /// could still be published for a height-less profile. It cannot, because of
  /// how `dailyEnergy` defines active — the SURPLUS of the Keytel rate over the
  /// basal minute, `Σ max(0, keytel(HR) − bmrDay/1440)`. The Mifflin term is
  /// inside active, not just inside total, so standing a height in moves the
  /// active scalar too: 35 y / 80 kg male, 600 wake minutes at 130 bpm, gives
  /// active 6500 kcal at 150 cm against 6383 at 195 cm, and total 8068 against
  /// 8232. Both are persisted to `day_result` and both are exported to Apple
  /// Health / Health Connect, so a 170 cm stand-in silently writes someone
  /// else's body into the user's health record — larger than the double-count
  /// this pass exists to remove, and against the rule that an absent input
  /// makes the dependent metric absent rather than imputed. Recovering an
  /// active figure with no height would mean not netting the basal minute out,
  /// which is precisely the double-count. So: real height, or no calories.
  ///
  /// The 1 Hz pipeline's early-read `calories` gates on height for the same
  /// reason, so Today does not show a figure the derived day then withdraws.
  @visibleForTesting
  static ({double active, double basal, double total, double walking})?
  wakeDayEnergy(
    List<double> wakeHrPerMin, {
    required Profile profile,
    required double? restingHr,
    int? dayMinutes,
    String? deviceFamily,
    List<double?>? cadenceSpmPerMin,
  }) {
    if (!profile.hasCalorieAnchors) return null;
    // The active gate is a %HRR flex point, so it needs BOTH ends of the
    // reserve. No resting HR, no gate — and no gate means every wake minute
    // bills as active. Abstain, same as an absent ceiling below.
    if (restingHr == null) return null;
    // `dailyEnergy`'s flex gate is a fraction of HRmax, so an absent ceiling is
    // an absent gate — the whole triple abstains rather than bill a day against
    // some other strap's number. See hr_max.dart.
    final hrmax = estimatedMaxHr(profile.ageYears, deviceFamily);
    if (hrmax == null) return null;
    final heightCm = profile.heightCm;
    if (heightCm == null) return null;
    // Off-skin samples are the package's 0 sentinel; billing them would credit
    // lost contact at the resting rate. The cadence series is filtered in the
    // SAME pass: `dailyEnergy` aligns the two by index, so dropping an HR
    // entry without dropping its cadence would price every later cadence
    // against the wrong minute.
    if (cadenceSpmPerMin != null &&
        cadenceSpmPerMin.length != wakeHrPerMin.length) {
      // A caller bug, but a derive pass is not the place to throw: no cadence
      // beats a misaligned one, and the HR half of the figure is still real.
      cadenceSpmPerMin = null;
    }
    final hr = <double>[];
    final cadence = cadenceSpmPerMin == null ? null : <double?>[];
    for (var i = 0; i < wakeHrPerMin.length; i++) {
      if (wakeHrPerMin[i] <= 0) continue;
      hr.add(wakeHrPerMin[i]);
      cadence?.add(cadenceSpmPerMin?[i]);
    }
    if (hr.isEmpty) return null;
    final e = ana.Calories.dailyEnergy(
      hr,
      profile: ana.WorkoutUserProfile(
        weightKg: profile.weightKg!,
        heightCm: heightCm,
        age: profile.ageYears!.toDouble(),
        sex: _workoutSex(profile.sex),
      ),
      hrmax: hrmax,
      restingHr: restingHr,
      dayMinutes: dayMinutes ?? 1440,
      cadenceSpmPerMin: cadence,
    );
    // Anchors that cannot define an active gate are an ABSENT day's energy,
    // not a day billed entirely as active. `dailyEnergy` abstains; so does the
    // day, which is what every other caller of this method already expects.
    if (e == null) return null;
    return (
      active: e.active,
      basal: e.basal,
      total: e.total,
      walking: e.walking,
    );
  }

  static double? _meanWake(List<double> xs) {
    if (xs.isEmpty) return null;
    var s = 0.0;
    for (final x in xs) {
      s += x;
    }
    return s / xs.length;
  }

  /// The whole activity half of a day: wake features, then the real-pedometer
  /// step and movement overrides, applied to [bundle] and [scalars] in the
  /// order production applies them. Returns the wake-features payload with the
  /// measured step count copied back in.
  ///
  /// Exists as one named method rather than three calls inline in
  /// [_computeDayBlocks] so a test can assert on the SCALAR PAIR a persisted
  /// day actually carries. The calorie invariant held in `wakeDayEnergy` and
  /// broke on the way out of it — a second `dailyEnergy` further down the
  /// sequence overwrote `calories_total` — and a test that only exercised the
  /// helper could not see that.
  @visibleForTesting
  static Map<String, dynamic> applyDayActivity({
    required Map<String, dynamic> bundle,
    required Map<String, dynamic> scalars,
    required Substrate daySub,
    required Profile profile,
    required int sleepOnsetSec,
    required int sleepOffsetSec,

    /// Local midnight opening this day, and the start of the NEXT local day —
    /// both from the day LABEL. `_DayBlocksInput.dayEndSec` is NOT this: it is
    /// the data edge (`daySub.lastTs + 1`), which is exactly the span-shaped
    /// denominator `_wearBlock` had to stop using. Passing it here would
    /// reinstate the bug under a different name.
    required int dayStartSec,
    required int dayCalendarEndSec,
    required int dataNowSec,
    int? viewNowSec,
    List<List<int>> wristOff = const [],
    List<List<int>> charging = const [],
    double? restingHr,
    double? dynFloorG,
    int liveStepsReal = 0,
    int liveStepsFromStrap = 0,
    int dynHistoryDays = 0,
    List<List<int>> stepSpans = const [],

    /// This day's `sessions` rows (`LocalDb.sessionsInRange`), for the
    /// zero-coverage credit below. Defaults to none — every existing caller
    /// keeps its old behaviour until it is threaded through.
    List<Map<String, dynamic>> sessions = const [],

    /// B88-02: the pipeline's zone set, so the day's zone minutes use the same
    /// bands as `zone_timeline`/`zone_source`. Null falls back to the age
    /// estimate, as before.
    ana.HeartRateZoneSet? zoneSet,
  }) {
    final wake = _buildWakeDayFeatures(
      daySub,
      profile,
      sleepOnsetSec: sleepOnsetSec,
      sleepOffsetSec: sleepOffsetSec,
      dayStartSec: dayStartSec,
      dayCalendarEndSec: dayCalendarEndSec,
      dataNowSec: dataNowSec,
      viewNowSec: viewNowSec,
      wristOff: wristOff,
      charging: charging,
      restingHr: restingHr,
      dynFloorG: dynFloorG,
      stepSpans: stepSpans,
      zoneSet: zoneSet,
    );
    // ACTIVE ENERGY WORKOUT-GAP CREDIT. `wake['calories']` above is built
    // ENTIRELY from `daySub.hr` — the day's own continuous 1 Hz trace — and
    // never once reads `sessions`. A workout scores its OWN calorie figure
    // through a completely separate pipeline (`computeManualSessionStats` /
    // the live-tick accumulator, reconciled in `reconcileSessionScore`), so a
    // session whose window the band's PPG lost contact for — commonly a
    // wrist-gripping or arm-swinging one, e.g. lifting or a brisk walk, next
    // to a low-motion one like Pilates that keeps contact — can be fully
    // scored on its own summary card while contributing exactly nothing to
    // Active Energy, because that window is a real, total gap in `daySub.hr`.
    //
    // Credited ONLY when a session's window has ZERO real HR samples in
    // `daySub` — never a partial one — which is what makes this safe: a
    // window `daySub.hr` already priced any of is left alone, so this can
    // never double-bill a minute the trace already counted. A day the trace
    // produced no figure for at all is left absent, same as always — this
    // fills a gap in an existing number, it does not fabricate one.
    if (wake['calories'] != null && sessions.isNotEmpty) {
      var credited = 0.0;
      for (final s in sessions) {
        if (s['status'] != 'done') continue;
        if ((s['private'] as num?)?.toInt() == 1) continue;
        // Active energy only (Build 90, algorithm 96). A row whose stored
        // calories are not known to be active — pre-Build 90 gross figures
        // kept as 'legacy', unexamined rows, vendor imports — is not credited:
        // adding resting energy to Active Energy would overstate it.
        if (s['calories_basis'] != kCaloriesBasisActive) continue;
        final sStart = (s['start_ts'] as num?)?.toInt();
        final sEnd = (s['end_ts'] as num?)?.toInt();
        final sCal = (s['calories'] as num?)?.toDouble();
        if (sStart == null ||
            sEnd == null ||
            sEnd <= sStart ||
            sCal == null ||
            sCal <= 0) {
          continue;
        }
        if (_hasHrCoverage(daySub, sStart, sEnd)) continue;
        credited += sCal;
      }
      if (credited > 0) {
        wake['calories'] = (wake['calories'] as num).toDouble() + credited;
        final total = wake['calories_total'];
        if (total != null) {
          wake['calories_total'] = (total as num).toDouble() + credited;
        }
        // Provenance for the envelope built in `_applyWakeDayFeatures` below —
        // without this, `calories_total`'s `inputs_used`/note would keep
        // claiming an hr_1hz-only figure while the emitted value silently
        // includes session-sourced kcal.
        wake['calories_session_credit'] = credited;
      }
    }
    // Build 89: A DAY IS NEVER LESS STRAINED THAN THE WORKOUTS INSIDE IT.
    // Build 90: applied BEFORE `_applyWakeDayFeatures` copies strain into the
    // day's scalars. Applied after it, the floor only reached `wake`, and the
    // stored strain every screen reads stayed 0.0 beside the walk. The
    // day's strain nets the quiet-waking baseline (still the population level,
    // edge#226) over every waking minute, so a wearer whose ordinary daytime
    // HR sits below it had a 3.4-strain walk cancelled by the quiet hours
    // around it and the day read 0.0 beside that walk. The finished sessions'
    // own net TRIMPs (strain is a log map, so they add as TRIMP, not as
    // strain) set a floor. It only ever raises a day that HAS a strain; it
    // never invents one, and a day without sessions is unchanged.
    final dayStrain = (wake['strain'] as num?)?.toDouble();
    if (dayStrain != null && sessions.isNotEmpty) {
      var net = 0.0;
      for (final s in sessions) {
        if (s['status'] != 'done') continue;
        final st = (s['strain'] as num?)?.toDouble();
        if (st != null && st.isFinite && st > 0) {
          net += ana.netTrimpFromStrain(st);
        }
      }
      final floor = ana.strainFromNetTrimp(net);
      if (floor > dayStrain) {
        wake['strain'] = floor;
        wake['strain_session_floor'] = true;
      }
    }
    _applyWakeDayFeatures(bundle, scalars, wake);
    _stepsAndEnergy(
      bundle,
      scalars,
      daySub,
      profile,
      liveStepsReal,
      liveStepsFromStrap,
      dynFloorG,
      dynHistoryDays,
    );
    // `_stepsAndEnergy` just wrote `steps` — REAL pedometer counts from
    // `live_coverage`, band 100 Hz or phone, never an estimate. `wake` was
    // built before that ran and deliberately leaves `steps` null: the
    // early-read path has no gait-capable source of its own and must not invent
    // one. `wake` is what `_persistWakeDayFeatures` stores and what the Today
    // repository reads until the full day result exists, so copy the measured
    // count back in — otherwise Today shows no steps on a day that really was
    // measured. `calories_total` is NOT in this list any more: it is written
    // once, by `_applyWakeDayFeatures`, and is already in `wake`.
    final measuredSteps = scalars['steps'];
    if (measuredSteps != null) wake['steps'] = measuredSteps;
    return wake;
  }

  static void _applyWakeDayFeatures(
    Map<String, dynamic> bundle,
    Map<String, dynamic>? scMap,
    Map<String, dynamic> wake,
  ) {
    final activeMin = (wake['active_min'] as num?)?.toDouble();
    if (activeMin != null) scMap?['active_min'] = activeMin;
    // STRAIN IS WRITTEN EVEN WHEN NULL — same rule as `steps`. This is the
    // recompute every surface reads (home tile, strain detail, metric_series,
    // the coach), so an abstaining day must ERASE what a previous derive wrote,
    // not leave it standing: days built before v68 carry a strain computed off
    // a daytime "resting" HR, and `if (strain != null)` kept exactly those.
    final strain = (wake['strain'] as num?)?.toDouble();
    scMap?['strain'] = strain;
    final calories = (wake['calories'] as num?)?.toDouble();
    if (calories != null) scMap?['calories'] = calories;
    final steps = (wake['steps'] as num?)?.toDouble();
    if (steps != null) scMap?['steps'] = steps;
    final caloriesTotal = (wake['calories_total'] as num?)?.toDouble();
    if (caloriesTotal != null) scMap?['calories_total'] = caloriesTotal;
    // The TDEE block is published HERE, from the same `wakeDayEnergy` result
    // that produced the two scalars above. `_stepsAndEnergy` used to emit it
    // from a SECOND `ana.Calories.dailyEnergy` call of its own — differently
    // gated, and over the whole 1440-minute day rather than the covered span —
    // so it silently overwrote `calories_total` with a figure that did not
    // belong to the same estimate as `calories`. `total - active` then handed
    // the Health export a basal that was wrong by tens of kcal/day in either
    // direction. One pass, one block.
    //
    // `calories_basal` is the third component of that one pass, and its
    // consumer is the `basal` field just below: publishing the figure the pass
    // actually produced, rather than re-deriving it as `total - active`, is
    // what makes the Health export's subtraction and this block agree by
    // construction instead of by arithmetic luck. It is deliberately NOT copied
    // into `scMap` — `day_result` carries the two scalars the app and the
    // export read, and a third one with no reader is a thing to keep in sync
    // for nothing.
    final caloriesBasal = (wake['calories_basal'] as num?)?.toDouble();
    if (caloriesTotal != null && calories != null && caloriesBasal != null) {
      // Disclosed only when it actually priced something: an input listed on a
      // day it contributed nothing to would claim pedometer coverage the day
      // may not have.
      final walking = (wake['calories_walking'] as num?)?.toDouble() ?? 0.0;
      final sessionCredit =
          (wake['calories_session_credit'] as num?)?.toDouble() ?? 0.0;
      bundle['calories_total'] = <String, dynamic>{
        'value': caloriesTotal.round(),
        'active': calories.round(),
        'basal': caloriesBasal.round(),
        'confidence': 0.5,
        'tier': 'ESTIMATE',
        'inputs_used': [
          'hr_1hz',
          'profile',
          if (walking > 0) 'live_coverage_pedometer',
          if (sessionCredit > 0) 'saved_session_calories',
        ],
        'note':
            'total daily energy: Mifflin BMR floor over the covered day + '
            'active Keytel surplus over the wake span (HR-flex)'
            '${walking > 0 ? ' + measured-cadence walking term '
                      '(CADENCE-Adults, ${walking.round()} kcal)' : ''}'
            '${sessionCredit > 0 ? ' + workout-gap session calories '
                      '(PPG lost the window, ${sessionCredit.round()} kcal)' : ''}',
      };
    }
    // WHY each of the above is absent, per figure. This recompute is the answer
    // every surface reads for the figures it owns, so its reasons win. NOTE
    // `bundle` here is the isolate's PATCH map, not the pure pipeline's bundle
    // — the two are merged at the `bundle.addAll(blocks.bundlePatch)` call
    // site, and that merge is where `trimp` (the pipeline's alone; nothing here
    // recomputes it) is carried across.
    bundle['absent_notes'] = <String, String>{
      for (final e in ((wake['absent_notes'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    };
    bundle['activity'] = wake['activity'];
    bundle['activity_curve'] = wake['activity_curve'];
    bundle['zones'] = wake['zones'];
    bundle['hr_stats'] = wake['hr_stats'];
    bundle['wear'] = wake['wear'];
  }

  /// The personal movement floor, estimated ONCE and then frozen.
  ///
  /// Returns the persisted value if one exists. Otherwise, once enough trailing
  /// `dyn_p90` days have accumulated, commits the median and returns it. Below
  /// that it returns null and the estimator abstains — deliberately, since a
  /// constant fallback is the exact failure this design removes.
  ///
  /// Why frozen: the floor is derived from the same signal it thresholds, so a
  /// continuously-recomputed floor tracks the user and reports a near-constant
  /// number regardless of behaviour (measured: 37 active minutes at 1x, 1.5x,
  /// 2x AND 3x activity, versus 23 -> 254 with a frozen floor).
  ///
  /// ORDER-INDEPENDENCE. The floor is ONE persisted scalar shared by every day,
  /// but `run()` dispatches days NEWEST-FIRST through a concurrent worker pool,
  /// so this read-modify-write is reached by several days at once. Three things
  /// keep the outcome from depending on which worker finishes last:
  ///
  ///   1. `_floorLock` serializes the whole read/decide/write, so two days can
  ///      never both observe "nothing stored" and both commit.
  ///   2. `daysSinceFrozen` is clamped at 0 (see [mfp.daysSinceFrozen]), so a
  ///      backfill day never reads as a stale floor and never triggers a
  ///      re-freeze just for being old.
  ///   3. `mayCommitFloorOn` stops an older day overwriting a newer freeze.
  ///
  /// Without these, a `kAlgoVersion` bump — which this very change forces —
  /// would re-derive the whole retained window and let sweep order decide every
  /// day's `active_min`. That is precisely what `_BaselineHistoryCache`'s own
  /// contract forbids for baselines.
  static Future<double?> _frozenMovementFloor(
    _BaselineHistoryCache history,
    String dayId,
  ) => _floorLock.run(() => _resolveMovementFloor(history, dayId));

  /// Serializes the shared-floor read-modify-write across concurrent day
  /// workers. See [_frozenMovementFloor].
  static final _AsyncLock _floorLock = _AsyncLock();

  static Future<double?> _resolveMovementFloor(
    _BaselineHistoryCache history,
    String dayId,
  ) async {
    final stored = await LocalDb.getMovementFloor();
    final hist = history.valuesBefore('dyn_p90', dayId);

    if (stored != null) {
      // Re-freeze only on a real change of scale, never on elapsed time alone.
      //
      // NOTE on the unwired signals: `shouldRefreezeFloor` also accepts
      // `deviceChanged` and `wristChanged`, and edge has no reliable source for
      // either yet (no persisted device identity, no wrist-selection history),
      // so they are deliberately NOT passed rather than passed as a fabricated
      // `false` that reads like a checked condition. `wearGapDays` IS
      // derivable — a run of days with no `dyn_p90` row means the band was not
      // worn — so it is computed and passed.
      final refreeze = ana.shouldRefreezeFloor(
        daysSinceFrozen: mfp.daysSinceFrozen(
          frozenOn: stored.frozenOn,
          dayId: dayId,
        ),
        wearGapDays: mfp.wearGapDays(
          have: history.datesFor('dyn_p90'),
          dayId: dayId,
        ),
      );
      if (!refreeze) return stored.floorG;

      // A re-freeze that CANNOT be satisfied must not destroy what we have.
      // Falling through to enrollment with thin history would return null and
      // make `active_min` vanish for the day — and that is reachable exactly
      // when re-freezing matters most (an old floor on a user whose recent
      // `dyn_p90` history was pruned or is sparse). Keep serving the existing
      // floor until a replacement can actually be computed.
      if (hist.length < ana.enrollmentDaysForFrozenFloor) return stored.floorG;

      // REACHABLE, and this is the case it exists for: an OLD backfill day that
      // trips the re-freeze rule (a 30-day wear gap before it is the common
      // one) and has enough prior history to recompute. Without this it would
      // overwrite the freeze a NEWER day just established, and since the sweep
      // runs newest-first and concurrently, sweep order would decide the floor.
      // A backfill day may CONSUME the shared floor; it may never move it.
      if (!mfp.mayCommitFloorOn(frozenOn: stored.frozenOn, dayId: dayId)) {
        return stored.floorG;
      }
    } else if (hist.length < ana.enrollmentDaysForFrozenFloor) {
      // Still enrolling, and nothing stored to fall back on. Return null so the
      // metric abstains and says so, rather than shipping a threshold we have
      // already proven will be re-derived.
      return null;
    }

    final floor = ana.personalDynFloorFromDailySummaries(hist);
    if (floor == null) return stored?.floorG;
    await LocalDb.putMovementFloor(
      floorG: floor,
      frozenOn: dayId,
      days: hist.length,
    );
    if (kDebugMode) {
      debugPrint(
        '[derive] movement floor FROZEN at '
        '${floor.toStringAsFixed(4)} g from ${hist.length} days ($dayId)',
      );
    }
    return floor;
  }

  /// Write the day's step count. REAL PEDOMETER MEASUREMENTS ONLY.
  ///
  /// The 1 Hz substrate contributes NOTHING here and must never do so again.
  /// The removed estimate multiplied 1 Hz "active minutes" by a walking cadence
  /// band; on a real user day it reported 2,645 steps against a true count
  /// under 400. Both halves of that conversion are invalid at 1 Hz:
  ///   * cadence is not identifiable (gait 1.4-2.3 Hz is sub-Nyquist; 80/100/
  ///     140/160 spm all alias to the same 0.333 Hz), and
  ///   * the minutes counted were never specifically ambulation — at the wrist,
  ///     arm work out-accelerates walking (stirring ~104 mg, chopping ~139 mg
  ///     vs walking ~66 mg ENMO), which is why wrist devices are documented
  ///     emitting 22-27 false steps/min during dishes and driving (O'Connell
  ///     2017) while missing slow walking at sensitivity 0.05.
  /// Two errors of OPPOSITE sign: no gain constant fixes both.
  ///
  /// So `steps` is absent unless something that can actually see gait measured
  /// it: the Tier A 100 Hz pedometer, or the phone's own pedometer (both land
  /// in `live_coverage`). No real source -> no number.
  ///
  /// Called BEFORE the movement-substrate guards, because it depends on none of
  /// them — see the call site.
  ///
  /// [bandSteps] is the gen5 strap's OWN pedometer total for the day (see
  /// [hardwareStepsFromCounter]) — a genuine on-wrist gait counter, not a 1 Hz
  /// inference, so it outranks the phone. Null on every gen4 day, and on a gen5
  /// day whose records predate schema v34; that is the absent case, not zero.
  static void _writeSteps(
    Map<String, dynamic> bundle,
    Map<String, dynamic>? scMap,
    int liveStepsReal, {
    int liveStepsFromStrap = 0,
    int? bandSteps,
  }) {
    // THE SOURCE LADDER, and where each rung is actually decided.
    //
    // Rungs 1 (band 100 Hz) and 3 (phone) are WINDOWED and were already settled
    // before this ran: `LocalDb.resolvedStepsForDay` walked the day's spans and
    // gave each one to the best source that covered it, so `liveStepsReal` is
    // already a sum of resolved spans and `liveStepsFromStrap` is the band's
    // share of it. Nothing here re-decides that.
    //
    // Rung 2, the gen5 ON-CHIP COUNTER, cannot join that sum honestly. It is a
    // cumulative u16 with no midnight reset and no timestamps of its own
    // (`hardwareStepsFromCounter` differences it across the day's records): a
    // whole-day total with no window behind it. Slicing it into spans would
    // mean inventing an extent for it, and adding it to windowed spans would
    // double-count every walk the other two already counted. So it stays a
    // WHOLE-DAY FALLBACK — used only when no span source covered the day at
    // all. That inversion is deliberate: whole-day precedence for this counter
    // is exactly the bug being fixed (622 steps published over the phone's
    // 18,856 on a day the strap synced for part of).
    final strap = liveStepsFromStrap.clamp(0, liveStepsReal);
    final phone = liveStepsReal - strap;
    // Phone only: a band count never stands in for the phone's.
    final steps = liveStepsReal;
    final haveRealSteps = steps > 0;
    if (haveRealSteps) {
      scMap?['steps'] = steps.toDouble();
    } else {
      scMap?.remove('steps');
    }
    bundle['steps'] = <String, dynamic>{
      'value': haveRealSteps ? steps : null,
      'real_measured': liveStepsReal,
      // What the strap's own pedometer counted, independent of which source
      // won. Null (never 0) when this generation has no counter at all.
      'band_measured': bandSteps,
      // WHICH SENSOR COUNTED WHAT, so a screen can say so instead of implying
      // the phone's count came off the wrist or the other way round. Only the
      // keys that contributed are present — a zero here would read as "that
      // sensor was there and counted nothing", which is a different claim.
      'by_source': haveRealSteps
          ? <String, int>{
              if (strap > 0) 'strap': strap,
              if (phone > 0) 'phone': phone,
            }
          : const <String, int>{},
      'source': !haveRealSteps
          ? null
          : (strap > 0 && phone > 0)
          ? 'mixed'
          : (strap > 0 ? 'strap' : 'phone'),
      'confidence': haveRealSteps ? 0.9 : 0.0,
      // NO TIER ON AN ABSENT METRIC. `ESTIMATE` here was actively wrong in two
      // ways: this code path never estimates anything (that is the whole point
      // of the change), and `Metric.parse` turns tier == ESTIMATE into
      // `beta: true`, which paints the estimate/beta badge onto a card that has
      // no number on it at all. `null` parses to `MetricTier.unknown`, which is
      // what "we did not measure this" actually is. `ABSENT` is deliberately
      // NOT invented: `Tier.all` in analytics is a closed set of four published
      // grades and the edge must not widen it from here.
      'tier': haveRealSteps ? 'HIGH' : null,
      // Likewise, nothing was used when nothing was measured.
      // NAMES THE SENSOR, not the table it came out of. `live_coverage_pedometer`
      // was the storage location and covered both the wrist and the pocket,
      // which is the one distinction the ladder exists to preserve. The UI
      // reads these to label the card.
      'inputs_used': !haveRealSteps
          ? const <String>[]
          : <String>[
              if (strap > 0) 'band_pedometer_100hz',
              if (phone > 0) 'phone_pedometer',
            ],
      'note': haveRealSteps
          ? ((strap > 0 && phone > 0)
                ? 'counted over measured windows only, each window by the '
                      'better sensor that was actually recording it — the '
                      'strap while it streamed, your phone the rest of the '
                      'time. Overlaps are counted once, and time no sensor '
                      'covered is not counted rather than estimated'
                : 'real pedometer count over measured windows only; time '
                      'outside those windows is not counted rather than '
                      'estimated')
          : 'no step count: nothing that can resolve gait measured this day. '
                'A 1 Hz wrist stream cannot count steps, so no number is shown '
                'instead of an invented one',
    };
  }

  /// STEPS (real pedometer counts ONLY) + movement minutes + total daily energy
  /// (TDEE), written into the bundle's `steps`/`movement` blocks + `scalars`.
  ///
  /// Steps = [liveStepsReal] and nothing else — the pedometer counts banked in
  /// `live_coverage` by a source that can actually resolve gait (the band's
  /// 100 Hz AN-2554 stream, or the phone's own pedometer). Time outside those
  /// windows is NOT counted and NOT estimated: with no real count the day has
  /// no step number at all. See the long note at the call site for why the old
  /// 1 Hz estimate was removed rather than recalibrated.
  ///
  /// Movement minutes are a separate, explicitly non-locomotion activity index
  /// computed over the whole day. Best-effort. Calories are NOT computed here —
  /// `_applyWakeDayFeatures` owns them, from one `wakeDayEnergy` pass.
  static void _stepsAndEnergy(
    Map<String, dynamic> bundle,
    Map<String, dynamic>? scMap,
    Substrate daySub,
    Profile profile,
    int liveStepsReal,
    int liveStepsFromStrap,
    double? dynFloorG,
    int dynHistoryDays,
  ) {
    try {
      // STEPS FIRST — they depend on NOTHING from the band substrate.
      //
      // `liveStepsReal` comes from `live_coverage`, i.e. the phone pedometer or
      // a live 100 Hz session. Both of the guards below protect the 1 Hz
      // MOVEMENT computation, and if the step assignment sat after them a day
      // with real measured phone steps but a thin band substrate (a day the
      // band barely synced, or a fresh install) would silently report no steps
      // at all — discarding a real measurement because an unrelated signal was
      // missing. Assign steps before anything can return early.
      // The strap's own pedometer, when this strap has one (gen5). Read off
      // `daySub` — already sliced to this calendar day — so the first record's
      // delta against yesterday's last is not carried across the boundary.
      _writeSteps(
        bundle,
        scMap,
        liveStepsReal,
        liveStepsFromStrap: liveStepsFromStrap,
        bandSteps: hardwareStepsFromCounter(
          daySub,
          cumulativeCounterModulus: ana.calibrationFor(
            _stepCounterModulus,
            daySub.deviceFamily,
          ),
        ),
      );

      if (daySub.length < 60) return;
      final motion = _motionMinutes(daySub);
      if (motion.isEmpty) return;

      // This day's own contribution to the personal floor, persisted to
      // metric_series so tomorrow's derive can anchor on it. Null for a day too
      // thin to summarise — we store nothing rather than a fabricated level.
      final dynSummary = ana.dailyDynSummary(motion);
      if (dynSummary != null) scMap?['dyn_p90'] = dynSummary;

      // MOVEMENT MINUTES run over the WHOLE day — no coverage exclusion.
      //
      // Minutes covered by a pedometer window used to be dropped here, because
      // steps were "real count over covered time + 1 Hz estimate over the rest"
      // and including both would double-count. That hybrid is gone: steps are
      // real-measured only and movement minutes are a separate quantity in a
      // different unit, so there is nothing to double-count. Excluding covered
      // minutes now would just silently under-report movement for exactly the
      // periods we know the user was active.
      final est = ana.dailyActiveMinutes(
        motion,
        personalDynFloorG: dynFloorG,
        // DAYS, and the parameter now says so. This used to be
        // `pooledMinutesAvailable`, a MINUTE count compared against a
        // 2000-minute floor, while every caller passed a day count — the
        // cold-start note read "have=3, need=2000" for a user three days in.
        // Analytics renamed it and now counts it against the 5-day floor it
        // was always describing.
        historyDaysAvailable: dynHistoryDays,
        // A CALENDAR DAY, as `enmoSeries` is given below. Without it the
        // coverage denominator is the worn SPAN, which excludes the unworn
        // ends: a day worn 4 h out of 24 published coverage 1.0.
        expectedMinutes: 1440,
      );
      final v = est.present ? est.value : null;

      // Movement minutes stay, as an explicitly non-locomotion activity index.
      //
      // IT DOES NOT WRITE `active_min`. That key is `_activeMinutes` — minutes
      // over the WAKE span where >20% of seconds showed a >5° z-angle change —
      // and this is ENMO bouts (≥3 min) over the FULL calendar day against a
      // personal g floor. Two algorithms, two windows, one key: `dailyActiveMinutes`
      // abstains until the floor freezes (~day 5), so the day it starts
      // answering, the user's 'active' trend stepped to a different quantity
      // with no change in behaviour — and stepped again on every re-freeze.
      // This figure is published under its own names, `movement` below and
      // `activity.movement_min`, and `active_min` has exactly one producer.
      bundle['movement'] = <String, dynamic>{
        'active_min': v?.activeMinutes,
        'bout_count': v?.boutCount,
        'dyn_floor_g': v?.dynFloorG,
        'coverage': v?.coverage,
        'confidence': est.present ? est.confidence : 0.0,
        'tier': 'ESTIMATE',
        // HR is NOT an input any more — the resting-HR gate was deleted in v56
        // after it changed active minutes by exactly zero on every day tested.
        'inputs_used': const ['dyn_amp_1hz', 'personal_dyn_floor'],
        'note': v == null
            ? (est.note ?? 'need_baseline')
            : 'minutes of sustained wrist movement — activity volume, NOT '
                  'walking, and deliberately not converted to steps',
      };
      // ENERGY IS NOT COMPUTED HERE. `_applyWakeDayFeatures` has already
      // published `calories`, `calories_total` and the TDEE block from the
      // single `wakeDayEnergy` pass, and this method must not touch any of
      // them. It used to run a second, differently-gated `dailyEnergy` of its
      // own and overwrite `calories_total` with it, which broke the one thing
      // the pair is supposed to guarantee: that `calories_total - calories` is
      // the day's basal. See the note in `_applyWakeDayFeatures`.
    } catch (e) {
      if (kDebugMode) debugPrint('[derive] steps/energy skipped: $e');
    }
  }

  Future<void> _persistWakeDayFeatures({
    required String dayId,
    required Map<String, dynamic> wake,
  }) async {
    final payload = <String, dynamic>{'day_id': dayId, ...wake};
    await LocalDb.putWakeDayFeatures(
      dayId: dayId,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(payload),
    );
  }

  static Map<String, dynamic> _buildWakeDayFeatures(
    Substrate daySub,
    Profile profile, {
    required int sleepOnsetSec,
    required int sleepOffsetSec,
    required int dayStartSec,
    required int dayCalendarEndSec,
    required int dataNowSec,
    int? viewNowSec,
    List<List<int>> wristOff = const [],
    List<List<int>> charging = const [],
    double? restingHr,
    double? dynFloorG,
    List<List<int>> stepSpans = const [],
    ana.HeartRateZoneSet? zoneSet,
  }) {
    final activeMin = _activeMinutes(daySub, sleepOnsetSec, sleepOffsetSec);
    final wear = _wearBlock(
      daySub,
      dayStartSec: dayStartSec,
      dayCalendarEndSec: dayCalendarEndSec,
      dataNowSec: dataNowSec,
      viewNowSec: viewNowSec,
      wristOff: wristOff,
      charging: charging,
    );
    final wakeSeries = _perMinuteMeanWake(
      daySub,
      sleepOnsetSec,
      sleepOffsetSec,
    );
    final perMin = wakeSeries.hr;
    // B88-02: each wake minute weighted by the time it actually recorded
    // (same rule as the day pipeline), so a gap-edge minute of one sample is
    // not a full minute of load.
    final wakeTs = <double>[
      for (var i = 0; i < daySub.hr.length && i < daySub.tsSec.length; i++)
        if (daySub.hr[i] > 0 &&
            !(sleepOffsetSec > sleepOnsetSec &&
                daySub.tsSec[i] >= sleepOnsetSec &&
                daySub.tsSec[i] < sleepOffsetSec))
          daySub.tsSec[i].toDouble(),
    ];
    final cover = ana.minuteCoverage(wakeTs, wakeSeries.keys);
    final minuteWeights = cover.length == perMin.length ? cover : null;
    final coveredMin = minuteWeights == null
        ? perMin.length.toDouble()
        : minuteWeights.fold<double>(0, (a, b) => a + b);
    // The day's MEASURED walking cadence, minute-aligned to the same wake
    // buckets — from the resolved `live_coverage` spans, so band/phone overlap
    // is already settled and a step is never priced twice. Null minutes are
    // exactly the minutes nobody's pedometer covered.
    final wakeCadence = stepSpans.isEmpty
        ? null
        : cadenceSpmForMinutes(wakeSeries.keys, stepSpans);
    final motion = _motionMinutes(daySub);
    final dayHrValid = <double>[
      for (final h in daySub.hr)
        if (h > 0) h.toDouble(),
    ];
    // NEVER IMPUTE A PROFILE. These used to default to age 30 / 70 kg / sex 'm'
    // / RHR 60 "so new users still get Strain" — and the results were then
    // persisted as REAL scalars (strain, calories, calories_total, steps) into
    // day_result AND metric_series for someone who never entered a profile.
    // That is a fabricated number wearing a real number's clothes, and it
    // contradicts the never-impute contract the rest of this layer (and
    // `Profile`'s own doc, and the pure `onehz_pipeline` which already gates on
    // exactly these fields) enforces. A missing input now makes the DEPENDENT
    // metric absent — the UI already renders "—" correctly.
    // age/weight are read by `wakeDayEnergy` straight off the profile now, so
    // they are no longer unpacked here — TRIMP only needs the sex constant.
    final sex = profile.sex?.toLowerCase();
    // ONE definition (hr_max.dart): null when age is unknown OR when we cannot
    // say which strap measured this day.
    final hrMax = estimatedMaxHr(profile.ageYears, daySub.deviceFamily);
    final rhrForTrimp = restingHr ?? profile.restingHrManual?.toDouble();
    double? strain;
    // Why each absent activity figure is absent, in the order the gates below
    // apply. Absence is never a bare nothing here: the day carries its own
    // reason PER FIGURE so every caller can say what is missing instead of
    // showing a dash — or, worse, guessing (the Strain screen used to blame a
    // missing resting HR on a day that had one, because the only reason written
    // down was attached to a metric it does not read).
    //
    // Same order and same vocabulary as `deriveDayBundle`'s pure half, which
    // gates on exactly these inputs; the two must not disagree about WHY.
    final ceilingAbsent = hrMax != null
        ? null
        : profile.ageYears == null
        ? needInputNote('age')
        // We know the age; we do not know what measured the HR, so we
        // have no ceiling to band it against.
        : ana.unknownFamilyNote(daySub.deviceFamily);
    String? strainAbsent = perMin.isEmpty
        ? needInputNote('wake_hr')
        : hrMax == null
        ? ceilingAbsent
        : dayHrValid.isEmpty
        ? needInputNote('hr_samples')
        : rhrForTrimp == null
        ? needInputNote('resting_hr')
        : sex == null
        ? needInputNote('sex')
        : null;
    // `wakeDayEnergy`'s own gates, named. It returns a bare null, so the reason
    // has to be reconstructed from the same inputs it reads — in its order.
    final caloriesAbsent = perMin.isEmpty
        ? needInputNote('wake_hr')
        // The whole energy pass is gated on having motion minutes to pro-rate
        // the basal floor over; a day with no accel never reaches it.
        : motion.isEmpty
        ? needInputNote('accel_1hz')
        : profile.ageYears == null
        ? needInputNote('age')
        : profile.weightKg == null
        ? needInputNote('weight_kg')
        : sex == null
        ? needInputNote('sex')
        : hrMax == null
        ? ceilingAbsent
        // Keytel does not read height; `dailyEnergy`'s ACTIVE
        // term nets out a Mifflin basal minute, which does.
        : profile.heightCm == null
        ? needInputNote('height_cm')
        : null;
    final zonesAbsent = perMin.isEmpty
        ? needInputNote('wake_hr')
        : ceilingAbsent;
    double? calories;
    double? steps; // stays null here — real counts only, see below
    double? movementMin;
    double? caloriesTotal;
    double? caloriesWalking;
    double? caloriesBasal;
    Map<String, int> zones = const {};
    if (perMin.isNotEmpty && hrMax != null) {
      // TRIMP needs a resting HR that is actually RESTING — a NOCTURNAL reading
      // (`scalars.rhr_nocturnal`, sleep-window only) or one the user entered —
      // and a real sex constant. Both are in the Banister formula itself.
      // `restingHr` used to arrive as `scalars.rhr`, which falls back to
      // daytime HR when no sleep was detected: ~20 bpm high on the days it
      // fired, which shrinks the HR reserve and manufactures strain out of
      // sitting still. No resting HR of either kind now means NO STRAIN.
      if (dayHrValid.isNotEmpty && rhrForTrimp != null && sex != null) {
        final trimp = ana.banisterTrimp(
          perMin,
          restingHr: rhrForTrimp,
          // B88-02: the zones' maximum — observed ceiling once it reaches the
          // age estimate, else the estimate — so TRIMP and zones agree.
          maxHr: zoneSet?.maxHr ?? hrMax,
          minuteWeights: minuteWeights,
          // Same sex normalisation the calorie path uses. This read `sex == 'f'`
          // alone, so a profile stored as 'female' (which the profile screen can
          // write) got female calorie coefficients and MALE TRIMP off the same
          // field. Banister publishes only two constants, so `nonbinary` has
          // nowhere else to go here.
          sex: _workoutSex(sex) == 'female' ? ana.Sex.female : ana.Sex.male,
        );
        if (trimp.present && trimp.value != null) {
          // `perMin` IS the wake window the TRIMP was accumulated over, so it
          // sets the quiet-waking baseline that gets subtracted. Passing the
          // observed length (not an assumed 24 h) is what stops a partial-wear
          // day from being charged a full day's overhead.
          final score = ana.strainScoreMetric(
            trimp.value,
            wakeMinutes: coveredMin,
            // Reference level, not this user's — see onehz_pipeline's
            // `strainMetric` for why, and edge#226 for the fix.
            quietHrr: ana.quietWakingHrr,
            female: _workoutSex(sex) == 'female',
          );
          if (score.present) strain = score.value;
        }
        // Every named input was there and the scorer still abstained. We do not
        // know why; saying so is the honest floor, and it is what the rule
        // "never a guessed cause" leaves when there is no cause to name.
        strainAbsent ??= strain == null ? kUnknownAbsenceNote : null;
      }
      // Zones are pure %HRmax bands — real as soon as HRmax is real.
      zones = _wakeZoneMinutes(
        daySub,
        sleepOnsetSec,
        sleepOffsetSec,
        hrMax,
        zoneSet: zoneSet,
      );
      // Calories are NOT computed here any more. Active and total both come
      // from the single `wakeDayEnergy` pass below, off this same wake series —
      // scoring active separately here, without the basal netting, is exactly
      // how the two figures drifted apart.
    }
    if (motion.isNotEmpty) {
      // STEPS ARE NOT COMPUTED HERE. This is the EARLY-READ path (what Today
      // shows before the full day result exists), and there is no gait-capable
      // source available to it — the real pedometer counts live in
      // `live_coverage` and are summed by `_stepsAndEnergy`, which overwrites
      // this artifact moments later via the copy-back below.
      //
      // It used to seed `steps` from the 1 Hz estimate so Today had something
      // to show immediately. That is exactly the fabrication being removed:
      // "something to show" is not a reason to invent a measurement. `steps`
      // stays null here and Today renders no step figure until a real count
      // exists.
      //
      // Movement minutes ARE computable from 1 Hz and are emitted below.
      final movementMetric = ana.dailyActiveMinutes(
        motion,
        personalDynFloorG: dynFloorG,
        // Same calendar-day denominator as the other call site; `motion` is
        // built from the whole day substrate here too.
        expectedMinutes: 1440,
      );
      if (movementMetric.present && movementMetric.value != null) {
        movementMin = movementMetric.value!.activeMinutes.toDouble();
      }
      // Mifflin BMR floor + Keytel active surplus, in ONE pass, so `calories`
      // and `calories_total` are two components of the same estimate rather
      // than two separate ones.
      //
      // ACTIVE reads the WAKE series and TOTAL's basal floor reads the whole
      // covered day. Feeding the whole-day series to the active term bills
      // sleep as exercise: `dailyEnergy`'s flex gate is 0.50*HRmax, i.e. only
      // 79.5 bpm at age 70, so an older sleeper spends the night above it.
      // `dayMinutes` pro-rates the basal floor over the span actually covered,
      // so a partial day is not billed a full 24 h BMR.
      final energy = wakeDayEnergy(
        perMin,
        profile: profile,
        // The same anchor the TRIMP above is scored against — a nocturnal RHR
        // or the one the user entered, never a daytime fallback.
        restingHr: rhrForTrimp,
        dayMinutes: motion.length,
        deviceFamily: daySub.deviceFamily,
        cadenceSpmPerMin: wakeCadence,
      );
      if (energy != null) {
        calories = energy.active;
        caloriesTotal = energy.total;
        caloriesBasal = energy.basal;
        caloriesWalking = energy.walking;
      }
    }
    // Same peak, same smoothing as the pipeline's copy and as every workout
    // producer — see `hr_max.dart` and the note beside the pipeline's `hrStats`.
    // A bare max over raw 1 Hz let one PPG transient be the day's "Peak HR"
    // (#127).
    final dayHrInt = [for (final h in dayHrValid) h.round()];
    final age = profile.ageYears?.round();
    final hrStats = dayHrValid.isEmpty
        ? null
        : {
            'max':
                smoothedMaxHr(dayHrInt, age: age) ??
                dayHrValid.reduce(math.max).round(),
            'min':
                smoothedMinHr(dayHrInt, age: age) ??
                dayHrValid.reduce(math.min).round(),
            'avg': _meanWake(dayHrValid)?.round(),
          };
    return {
      'active_min': activeMin,
      'movement_min': movementMin,
      'strain': strain,
      // Machine-readable reason `strain` is null (see `strainAbsent`). Null
      // when a strain WAS produced.
      'strain_absent': strain == null ? strainAbsent : null,
      // …and the same, per figure, for the rest of the activity family. A key
      // is present ONLY when that figure is absent. `_applyWakeDayFeatures`
      // merges this onto the bundle's `absent_notes`, which is what the serve
      // seam attaches to the value it hands a screen — see the note there.
      'absent_notes': <String, String>{
        if (strain == null) 'strain': strainAbsent ?? kUnknownAbsenceNote,
        if (zones.isEmpty) 'zones': zonesAbsent ?? kUnknownAbsenceNote,
        if (hrMax == null && ceilingAbsent != null)
          'max_hr_used': ceilingAbsent,
        if (calories == null) 'calories': caloriesAbsent ?? kUnknownAbsenceNote,
        if (caloriesTotal == null)
          'calories_total': caloriesAbsent ?? kUnknownAbsenceNote,
      },
      'calories': calories,
      'steps': steps,
      'calories_total': caloriesTotal,
      // Carried alongside so the TDEE block can be published from the same pass
      // instead of being re-derived (or, as it once was, recomputed by a second
      // caller with different gating). Not a user-facing scalar: the Health
      // export derives basal as `calories_total - calories`, and this is here to
      // make sure that subtraction and this figure are the same number.
      'calories_basal': caloriesBasal,
      // How much of `calories` came from the measured-cadence walking term
      // rather than HR (0 when no pedometer coverage priced anything). Carried
      // for the TDEE block's disclosure — a figure whose provenance changed
      // must say so in `inputs_used`.
      'calories_walking': caloriesWalking,
      'wear_min': (wear['worn_min'] as num?)?.toDouble(),
      'activity': {
        'value': activeMin,
        'active_min': activeMin,
        'movement_min': movementMin,
        'confidence': 0.6,
        'tier': 'ESTIMATE',
        'inputs_used': const ['accel_1hz'],
        'note':
            'minutes of wrist movement over wake (1 Hz). This is activity '
            'volume, NOT walking, and is never converted to steps: at the '
            'wrist, arm work registers as strongly as ambulation. Real step '
            'counts come only from the 100 Hz or phone pedometer',
      },
      'activity_curve': _activityCurve(daySub),
      'zones': zones,
      'hr_stats': hrStats,
      'wear': wear,
    };
  }

  /// Active minutes over the WAKE span — a coarse 1 Hz movement proxy.
  ///
  /// NULL, not 0, when nothing was countable. A gen5 day (or a gen4
  /// R10-historical one) decodes 1 Hz records with no usable accel, so every
  /// second is skipped below and the loop falls out with `active == 0` — which
  /// published "0 active minutes" as a measurement for a fully-worn band.
  static int? _activeMinutes(
    Substrate s,
    int sleepOnsetSec,
    int sleepOffsetSec,
  ) {
    final n = s.length;
    if (n < 60) return null;
    final ang = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      ang[i] = ana.zAngle(s.ax[i], s.ay[i], s.az[i]);
    }
    const moveDeg = 5.0;
    const activeFrac = 0.20;
    final moveSec = <int, int>{};
    final totSec = <int, int>{};
    for (var i = 1; i < n; i++) {
      // A second with no gravity vector contributes to NEITHER count: it has a
      // z-angle of exactly 0.0°, so counting it as denominator would read as
      // stillness and the fraction below would be diluted by missing data.
      if (!s.accelPresentAt(i) || !s.accelPresentAt(i - 1)) continue;
      final t = s.tsSec[i];
      if (sleepOffsetSec > sleepOnsetSec &&
          t >= sleepOnsetSec &&
          t < sleepOffsetSec) {
        continue;
      }
      final m = t ~/ 60;
      totSec[m] = (totSec[m] ?? 0) + 1;
      if ((ang[i] - ang[i - 1]).abs() > moveDeg) {
        moveSec[m] = (moveSec[m] ?? 0) + 1;
      }
    }
    if (totSec.isEmpty) return null;
    var active = 0;
    totSec.forEach((m, tot) {
      if (tot > 0 && (moveSec[m] ?? 0) / tot >= activeFrac) active++;
    });
    return active;
  }

  static List<ana.MotionMinute> _motionMinutes(Substrate s) {
    final samples = <ana.AccelSample>[
      for (var i = 0; i < s.length; i++)
        ana.AccelSample(
          s.tsSec[i] * 1000.0,
          s.ax[i],
          s.ay[i],
          s.az[i],
          // Wear (HR locked) AND a real gravity vector — either missing makes
          // the second unusable for ENMO, not a still one.
          valid: s.hr[i] > 0 && s.accelPresentAt(i),
        ),
    ];
    // 1440 = a calendar day. Both callers pass the day substrate, and without
    // it `EnmoResult.coverage` divides by the SPAN of minutes that had a
    // sample — so a day worn 4 h out of 24 reported coverage 1.0. Only
    // `.minutes` is read here today; passing it keeps the result honest if
    // coverage is ever surfaced.
    return ana.enmoSeries(samples, expectedMinutes: 1440).minutes;
  }

  /// See `workoutSex` in profile.dart — the one definition, shared with the
  /// pure pipeline, the live tick and manually logged sessions.
  static String _workoutSex(String? sex) => workoutSex(sex);

  // NOTE: `advanced_sleep` (`{present:false}`) is a constant stub emitted
  // inside [_computeDayBlocks] (the offloaded second half). If a real
  // AdvancedSleepStager pass is ever re-homed, put it back there so it stays
  // OFF the calling isolate. `detected_workouts` used to be listed here too and
  // is gone — see the note at its old site in [_computeDayBlocks].

  /// Per-5-min movement-level curve over the whole day ([{t, v}], v = fraction
  /// of seconds in the bucket with a ≥5° wrist-orientation change, 0..1). The
  /// honest 1 Hz movement signal (same basis as active-minutes) for the "Your
  /// day" Movement view. Sleep is NOT excluded — the curve naturally dips there.
  static List<Map<String, dynamic>> _activityCurve(Substrate s) {
    final n = s.length;
    if (n < 60) return const [];
    final ang = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      ang[i] = ana.zAngle(s.ax[i], s.ay[i], s.az[i]);
    }
    const bucketSec = 300; // 5 min
    final move = <int, int>{}, tot = <int, int>{};
    for (var i = 1; i < n; i++) {
      // Absent accel is not stillness — see _activeMinutes.
      if (!s.accelPresentAt(i) || !s.accelPresentAt(i - 1)) continue;
      final b = s.tsSec[i] ~/ bucketSec;
      tot[b] = (tot[b] ?? 0) + 1;
      if ((ang[i] - ang[i - 1]).abs() > 5.0) move[b] = (move[b] ?? 0) + 1;
    }
    final out = <Map<String, dynamic>>[];
    final keys = tot.keys.toList()..sort();
    for (final b in keys) {
      out.add({
        't': b * bucketSec,
        'v': double.parse(((move[b] ?? 0) / tot[b]!).toStringAsFixed(3)),
      });
    }
    return out;
  }

  /// On/off-wrist segments over the day from RECORD PRESENCE — the runs,
  /// first/last on, longest off gap, worn minutes + time-coverage.
  ///
  /// Wear is whether a 1 Hz record EXISTS, not whether HR locked. The band logs
  /// to flash only while on-wrist (off-wrist it stops and emits WRIST_OFF), so a
  /// record means worn. The old `hr>0` rule misread normal daytime PPG drop-out
  /// (HR only locks on a still wrist with good optical contact — mostly SLEEP)
  /// as off-wrist, collapsing a 24 h-worn day to ~the sleep window (~7-8 h). Off
  /// periods are now GAPS in the record stream longer than [offGapSec].
  ///
  /// CAVEAT: this assumes the band does NOT keep logging while off-wrist. If a
  /// future firmware streams off-wrist records, add a skin-temp/motion on-body
  /// gate here (the substrate carries accel + skinTemp).
  ///
  /// Coverage uses elapsed time through the durable record frontier. Worn
  /// minutes share metric_series' bridged record-minute definition. Only
  /// WRIST reports establish off-wrist time; the unsynced tail is pending.
  static Map<String, dynamic> _wearBlock(
    Substrate s, {
    required int dayStartSec,
    required int dayCalendarEndSec,
    required int dataNowSec,
    int? viewNowSec,
    List<List<int>> wristOff = const [],
    List<List<int>> charging = const [],
  }) => ana.dayWearBlock(
    s.tsSec,
    startSec: dayStartSec,
    endSec: math.min(viewNowSec ?? dataNowSec, dayCalendarEndSec),
    frontierSec: dataNowSec + 1,
    offWrist: wristOff,
    charging: charging,
  );

  /// Waking ultradian HRV: RMSSD over 5-min buckets of the DAY's RR that falls
  /// OUTSIDE the sleep window (the daytime autonomic rhythm). Timeline + mean.
  /// All-day rolling-RMSSD curve over the 24/7 RR (epoch-stamped {t,v}), for the
  /// Timeline graph. 5-min sliding window, emitted ~each minute. Inline artifact
  /// gate (plausible RR 300–2000 ms) — daytime RR is noisier/motion-confounded,
  /// so this is a context line, not the nocturnal recovery RMSSD.
  /// Test seam: counts window evaluations, for the same reason as
  /// [debugRespAttempts] — the fix is about how often the O(window) sum runs.
  @visibleForTesting
  static int debugHrvAttempts = 0;

  @visibleForTesting
  static List<Map<String, num>> dayHrvCurve(Substrate s) {
    if (s.rrMs.length < 10 || s.rrTsMs.length != s.rrMs.length) return const [];
    // B88-03: the shared rolling-RMSSD rule — the headline's cleaning and
    // time-adjacency, ≥60% beat coverage per window — instead of differencing
    // straight down a filtered list, which paired beats across gaps and
    // across every dropped beat.
    debugHrvAttempts++;
    return [
      for (final pt in ana.rollingRmssd(s.rrMs, s.rrTsMs))
        if (pt.rmssd <= 220)
          {'t': pt.tSec, 'v': double.parse(pt.rmssd.toStringAsFixed(1))},
    ];
  }

  /// The day's RESTING breathing-rate floor (epoch {t,v} br/min) via rolling
  /// RSA on the 24/7 RR. 3-min window emitted ~every 5 min; absent windows (too
  /// few/too noisy beats) are skipped — never fabricated.
  ///
  /// RESP-05 — every window is MOTION-GATED before the estimator runs (see
  /// [_respQuietFraction]). This is not "your breathing rate today" and it is
  /// never a value during activity: RSA amplitude collapses under motion, so a
  /// moving window cannot resolve a breathing rate at all. **Most days produce
  /// nothing, and that is the correct output.**
  ///
  /// Test seam: replaces the RSA estimator, so the ABSENT branch — the one that
  /// used to strand the cadence cursor and re-run a triple Lomb-Scargle per beat
  /// — can be exercised deterministically. It needs a seam because no synthetic
  /// RR reliably makes the real estimator abstain: the behaviour comes from real
  /// movement-confounded daytime data, which is exactly what is hard to fake.
  @visibleForTesting
  static double? Function(List<double> nn, List<double> nnt)?
  debugRespEstimator;

  /// Test seam: counts estimator ATTEMPTS. The cost fix is about how often the
  /// estimator runs, not about what it returns, so the attempt count is the only
  /// thing that actually distinguishes the fixed code from the broken code.
  @visibleForTesting
  static int debugRespAttempts = 0;

  /// Fraction of a candidate resp window's seconds that must be PRESENT AND
  /// STILL before the estimator is allowed to run (RESP-05).
  ///
  /// RSA amplitude collapses under motion and the tachogram's Nyquist falls
  /// with heart rate, so a window with movement in it physically cannot resolve
  /// a normal breathing rate — the estimator does not fail loudly there, it
  /// returns a confident wrong number or abstains at random. 0.9 of 180 s is
  /// 162 still seconds: it tolerates the odd re-orientation and rejects
  /// anything that is a walk. It also subsumes coverage — a second with no
  /// gravity vector cannot be counted still (absence is not stillness), so a
  /// half-observed window fails the same test.
  static const double _respQuietFraction = 0.9;

  /// Test seam: counts windows REJECTED by the stillness gate above.
  @visibleForTesting
  static int debugRespGateRejects = 0;

  @visibleForTesting
  static List<Map<String, num>> dayRespCurve(Substrate s) {
    // RESP-05 — the gate is per-FAMILY, and an unknown strap gets no cut rather
    // than gen4's (device.dart contract). Refusing the whole curve is the
    // correct output for every pre-schema-41 day and every import: we cannot
    // say those seconds were still, and an ungated daytime RSA number is the
    // thing this item exists to stop publishing.
    final cut = ana.calibrationFor(_quietEnmoCutG, s.deviceFamily);
    if (cut == null) return const [];
    // B88-04: a second is STILL when its gravity magnitude sits within [cut]
    // (0.02 g) of THAT WINDOW's own median magnitude — relative, not
    // |magnitude − 1 g|. This band's still magnitude sits anywhere in
    // ~0.93–1.07 g depending on wrist posture (plus a ~4.6 % scale), so the
    // absolute test rejected most still sleeping windows and emptied the
    // breathing lane. Movement still breaks it; a missing vector is never
    // still (absence is not stillness).
    final mag = List<double>.filled(s.length, double.nan);
    for (var i = 0; i < s.length; i++) {
      if (!s.accelPresentAt(i)) continue;
      mag[i] = math.sqrt(
        s.ax[i] * s.ax[i] + s.ay[i] * s.ay[i] + s.az[i] * s.az[i],
      );
    }
    int stillIn(int from, int to) {
      final present = [
        for (var k = from; k < to; k++)
          if (!mag[k].isNaN) mag[k],
      ]..sort();
      if (present.isEmpty) return 0;
      final m = present.length.isOdd
          ? present[present.length ~/ 2]
          : (present[present.length ~/ 2 - 1] + present[present.length ~/ 2]) /
                2;
      return present.where((v) => (v - m).abs() <= cut).length;
    }

    final ts = <double>[], rr = <double>[];
    for (var i = 0; i < s.rrMs.length; i++) {
      final v = s.rrMs[i];
      if (v >= 300 && v <= 2000) {
        ts.add(s.rrTsMs[i]);
        rr.add(v);
      }
    }
    if (rr.length < 60) return const [];
    const winMs = 180000.0; // 3 min
    final out = <Map<String, num>>[];
    var lo = 0;
    var lastEmit = -1e18;
    // Cursors into s.tsSec for the window bounds. Both `ts[lo]` and `ts[i]` are
    // non-decreasing across the loop, so these only ever move forward.
    var qLo = 0, qHi = 0;
    for (var i = 0; i < rr.length; i++) {
      while (ts[i] - ts[lo] > winMs) {
        lo++;
      }
      if (i - lo >= 30 && ts[i] - lastEmit > 300000) {
        // 5-min cadence
        // STILLNESS GATE, BEFORE the estimator. Rejecting here is also where
        // the perf win lives: the triple Lomb-Scargle never runs on a window
        // that could not have produced a resting rate anyway.
        final loSec = (ts[lo] / 1000).floor();
        final hiSec = (ts[i] / 1000).ceil();
        while (qLo < s.length && s.tsSec[qLo] < loSec) {
          qLo++;
        }
        if (qHi < qLo) qHi = qLo;
        while (qHi < s.length && s.tsSec[qHi] < hiSec) {
          qHi++;
        }
        final spanSec = hiSec - loSec;
        final stillSec = stillIn(qLo, qHi);
        if (spanSec <= 0 || stillSec < _respQuietFraction * spanSec) {
          // Advance the cadence cursor on a rejection too — otherwise a moving
          // stretch re-tests (and re-scans) once per beat, which is the same
          // shape as the v60 bug this loop already carries a fix for.
          debugRespGateRejects++;
          lastEmit = ts[i];
          continue;
        }
        final nn = rr.sublist(lo, i + 1);
        final t0 = ts[lo];
        final nnt = [for (var k = lo; k <= i; k++) ts[k] - t0];
        debugRespAttempts++;
        final seam = debugRespEstimator;
        final double? brpm;
        if (seam != null) {
          brpm = seam(nn, nnt);
        } else {
          final clock = ana.rrBeatClock(nn, rrTsMs: nnt);
          final est = ana.rsaRespRate(
            nn,
            clock.timesMs,
            artifactFraction: 0.15,
            gapBefore: clock.reanchorBefore,
          );
          brpm = est.present ? est.value!.brpm : null;
        }
        // Advance the cadence cursor on every ATTEMPT, not just on a successful
        // estimate. Daytime RSA is movement-confounded (see above), so absent is
        // the common case — and while lastEmit sat inside the success branch a
        // confounded stretch re-ran the triple Lomb-Scargle once per BEAT
        // instead of once per 5 min. That is what blew the day-blocks budget.
        lastEmit = ts[i];
        if (brpm != null) {
          out.add({
            't': (ts[i] / 1000).round(),
            'v': double.parse(brpm.toStringAsFixed(1)),
          });
        }
      }
    }
    return out;
  }

  /// All-day RELATIVE skin-temperature trend (epoch {t,v}). Per-5-min mean ADC
  /// expressed as a delta from the day's median — RELATIVE only, no absolute °C
  /// (the band has no calibrated temperature). A slow context line.
  static List<Map<String, num>> _daySkinTempCurve(Substrate s) {
    // B88-01: no curve from an unverified channel (WHOOP 4 optical counts).
    if (!hasVerifiedSkinTemp(s.deviceFamily)) return const [];
    final bins = <int, List<double>>{};
    for (var i = 0; i < s.skinTemp.length && i < s.tsSec.length; i++) {
      final v = s.skinTemp[i];
      if (v != null) (bins[s.tsSec[i] ~/ 300] ??= []).add(v.toDouble());
    }
    if (bins.length < 3) return const [];
    final keys = bins.keys.toList()..sort();
    final means = {
      for (final k in keys)
        k: bins[k]!.reduce((a, b) => a + b) / bins[k]!.length,
    };
    final sorted = means.values.toList()..sort();
    final med = sorted[sorted.length ~/ 2];
    return [
      for (final k in keys)
        {'t': k * 300, 'v': double.parse((means[k]! - med).toStringAsFixed(1))},
    ];
  }

  /// Quiet-second ENMO cut (g), per sensor package.
  ///
  /// ENMO here is `||a|| − 1 g`, the amplitude index used by `enmoSeries`.
  /// Restlessness uses arm-angle change separately. A sedentary/still wrist sits at ~0.01-0.02 g and
  /// walking at ~0.066 g, so 0.02 g separates sitting from moving without
  /// pretending to separate postures. Listed per family because the cut is only
  /// meaningful against that family's accel scale; an unknown strap gets no cut
  /// and the whole block refuses.
  /// On-chip step counters whose BEHAVIOUR we have established, by the family
  /// stamped on the row: the modulus it wraps at, and — the part that actually
  /// matters — that it is cumulative and does NOT reset at midnight. Both are
  /// verified for gen5 (see `Substrate.stepCount`). A stamp that is not a key
  /// here, including no stamp at all, gets no band-step number: summing deltas
  /// off a resetting counter loses the day's whole pre-sync prefix, and it
  /// cannot be told apart from a wrap afterwards. See
  /// [hardwareStepsFromCounter].
  static const Map<String, int> _stepCounterModulus = {'gen5': 65536};

  static const Map<String, double> _quietEnmoCutG = {
    'gen4': 0.02,
    'gen5': 0.02,
  };

  @visibleForTesting
  static Map<String, dynamic> daytimeHrv(
    Substrate s,
    int onsetSec,
    int offsetSec,
  ) => _daytimeHrv(s, onsetSec, offsetSec);

  /// Daytime HRV, MOTION-GATED. The gate is the feature, not a refinement: an
  /// RR series filtered only on plausibility lets a bin of walking into the
  /// average as low HRV, and the number then reads as stress when it is
  /// posture. Only beats whose own second was still — a real gravity vector,
  /// ENMO under the family's quiet cut — are paired.
  ///
  /// Absent accel is NOT stillness (see [Substrate.accelPresentAt]), and an
  /// unknown device family has no cut we can stand behind. Both refuse.
  ///
  /// THIS IS ONE RELABEL AWAY FROM A BODY BATTERY, AND IT MUST NOT TAKE THE
  /// STEP. quiet windows described as variability is the honest residue; a
  /// continuous all-day stress score or a depleting battery icon built on this
  /// series is refused, and the pressure to relabel will arrive from outside
  /// the code rather than from anything here. two independent reasons:
  ///   * the signal. wrist PPG beat timing collapses under motion without
  ///     aggressive quality gating — which is why this function gates at all —
  ///     so the waking hours a stress score would describe are exactly the
  ///     hours its input is worst. gen4 has no per-beat quality flag at all.
  ///     CORRECTION, schema 43: gen5's `signalQualityLogVariance` is no longer
  ///     dropped — it is decoded, mapped and written to
  ///     `decoded_onehz.signal_quality_logvar`, and this comment claimed
  ///     otherwise for three schema versions. It is still not READ (it is in
  ///     neither substrate column list), and wiring it would not rescue a
  ///     stress score: it exists on gen5/MG only, so gating on it means the
  ///     same night measured by two straps answers differently — which is the
  ///     one thing a metric that enters a cross-device baseline may never do.
  ///     A gen5-only within-night RANK or WEIGHT is defensible; a percentage,
  ///     a bar, or anything a gen4 user could compare against is not, because
  ///     the scale is the band's own with no units and no calibration.
  ///   * the construct. the systematic evaluation of 14 vendor composite
  ///     scores found NONE with independent peer-reviewed validation. the
  ///     inputs validate; the composite does not, and a depleting battery
  ///     invents a physiological quantity that does not exist — which teaches
  ///     the user to distrust a real body for disagreeing with a made-up one.
  /// so: no score, no 0-100, no battery, no gauge, no "current stress". a
  /// timeline of RMSSD over still minutes, labelled as variability, is the
  /// whole allowed surface.
  static Map<String, dynamic> _daytimeHrv(
    Substrate s,
    int onsetSec,
    int offsetSec,
  ) {
    const binSec = 300;
    final cut = ana.calibrationFor(_quietEnmoCutG, s.deviceFamily);
    if (cut == null) {
      return {
        'timeline': const <Map<String, dynamic>>[],
        'mean_rmssd': null,
        'n_buckets': 0,
        'note': ana.unknownFamilyNote(s.deviceFamily),
      };
    }
    // The seconds we can call still. Built once over the day substrate; a
    // second with no gravity vector never lands here, so it can only break a
    // pair, never join one.
    final quiet = <int>{};
    for (var i = 0; i < s.length; i++) {
      if (!s.accelPresentAt(i)) continue;
      final mag = math.sqrt(
        s.ax[i] * s.ax[i] + s.ay[i] * s.ay[i] + s.az[i] * s.az[i],
      );
      if ((mag - 1.0).abs() <= cut) quiet.add(s.tsSec[i]);
    }
    // B88-03: the shared rolling-RMSSD rule over 5-min bins. Only still beats
    // outside the sleep window may enter; any other beat breaks adjacency, so
    // a pair can never span movement, the night or a gap.
    bool include(double tsMs) {
      final tSec = tsMs ~/ 1000;
      if (offsetSec > onsetSec && tSec >= onsetSec && tSec < offsetSec) {
        return false;
      }
      return quiet.contains(tSec);
    }

    final timeline = <Map<String, dynamic>>[];
    final means = <double>[];
    if (s.rrMs.length == s.rrTsMs.length) {
      for (final pt in ana.rollingRmssd(
        s.rrMs,
        s.rrTsMs,
        windowSec: binSec,
        stepSec: binSec,
        minPairs: 5,
        include: include,
      )) {
        // `n` is how many quiet adjacent pairs this bin is built from, so the
        // card can say how thin a reading is.
        timeline.add({
          't': pt.tSec - binSec,
          'rmssd': (pt.rmssd * 10).round() / 10.0,
          'n': pt.pairs,
        });
        means.add(pt.rmssd);
      }
    }
    final mean = means.isEmpty
        ? null
        : means.reduce((a, c) => a + c) / means.length;
    return {
      'timeline': timeline,
      'mean_rmssd': mean == null ? null : (mean * 10).round() / 10.0,
      'n_buckets': timeline.length,
    };
  }

  /// Nocturnal restlessness from sleep-window orientation change: minutes with
  /// movement, number of distinct movement bouts, longest still stretch (min).
  static Map<String, dynamic> _restlessness(Substrate s) {
    final n = s.length;
    if (n < 60) {
      return {
        'restless_min': null,
        'movement_bouts': null,
        'longest_still_min': null,
      };
    }
    const moveDeg = 5.0;
    final byMinMove = <int, int>{}, byMinTot = <int, int>{};
    for (var i = 1; i < n; i++) {
      // Absent accel is not stillness — see _activeMinutes.
      if (!s.accelPresentAt(i) || !s.accelPresentAt(i - 1)) continue;
      final m = s.tsSec[i] ~/ 60;
      byMinTot[m] = (byMinTot[m] ?? 0) + 1;
      final d =
          (ana.zAngle(s.ax[i], s.ay[i], s.az[i]) -
                  ana.zAngle(s.ax[i - 1], s.ay[i - 1], s.az[i - 1]))
              .abs();
      if (d > moveDeg) byMinMove[m] = (byMinMove[m] ?? 0) + 1;
    }
    final keys = byMinTot.keys.toList()..sort();
    // Nothing countable — a night whose records carry no gravity vector clears
    // the `n < 60` gate above and then skips every second, and returning the
    // zeros below claims a perfectly still, unbroken night measured from
    // nothing. Same answer as the thin-data branch: absent.
    if (keys.isEmpty) {
      return {
        'restless_min': null,
        'movement_bouts': null,
        'longest_still_min': null,
      };
    }
    var restless = 0, bouts = 0, longestStill = 0, curStill = 0;
    var prevMoved = false;
    for (final m in keys) {
      final moved = (byMinMove[m] ?? 0) / (byMinTot[m] ?? 1) >= 0.20;
      if (moved) {
        restless++;
        if (!prevMoved) bouts++;
        curStill = 0;
      } else {
        curStill++;
        if (curStill > longestStill) longestStill = curStill;
      }
      prevMoved = moved;
    }
    return {
      'restless_min': restless,
      'movement_bouts': bouts,
      'longest_still_min': longestStill,
    };
  }

  /// Sleep periods: the main sleep plus the naps [_attachNaps] already found.
  ///
  /// This used to run its OWN nap detector — 20-min runs of still, on-wrist
  /// minutes — in parallel with `detectNaps`. Two detectors, two answers, two
  /// screens: a private regression fixture produced a period here while
  /// `naps` reported `count: 0`. One source per concern (AGENTS §3.8), so the
  /// naps are now passed in rather than re-derived.
  ///
  /// Every period speaks the SAME contract the Sleep-periods screen reads
  /// (`onset_ts`/`wake_ts`/`duration_min`/`efficiency`/`confidence`), and
  /// `duration_min` is minutes ASLEEP for both the main sleep and naps — they
  /// were previously different units under one label, then summed.
  ///
  /// [naps] is NULL when the nap detector could not judge the day at all (as
  /// opposed to an empty list, which means "judged, and there were none"). An
  /// unjudged day has an unknown NUMBER of periods, not just unknown durations,
  /// so the total is unknown for exactly the same reason a null `duration_min`
  /// makes it unknown — and `nap_min` is already left unwritten in that case.
  /// Publishing `total_asleep_min = mainTstMin` there would state a complete
  /// day total while `naps.value` is null, which is internally inconsistent.
  /// The strap's own CHARGING_ON/OFF spans that fall INSIDE the scored sleep
  /// window — published as a caveat on the night, never as a reason to drop it.
  ///
  /// Why `wear` cannot see this: a battery-pack swap is not a wrist-off event.
  /// The pack clips onto the strap while the strap stays on the wrist, so the
  /// band keeps logging 1 Hz records the whole time and every wear signal we
  /// have — record presence, and the band's own WRIST_ON/OFF, which `wear`
  /// matches to the minute — correctly says "worn". Measured on a real 9-day
  /// export, 2 of 9 nights contained CHARGING_ON + BATTERY_PACK_CONNECTED +
  /// BATTERY_PACK_REMOVED inside the sleep window and were scored, staged and
  /// fed into baselines with nothing attached.
  ///
  /// NO CONFIDENCE PENALTY, deliberately. A confidence number here is a claim
  /// about how well we measured THIS NIGHT'S SLEEP, and the mechanism does not
  /// support that claim: the band is on the wrist, the PPG is against skin, and
  /// beat timing — which is what the stager and every HRV metric actually run
  /// on — has no pathway to degrade because a battery is sitting on the strap.
  /// Multiplying the night's confidence down would be inventing a measured
  /// degradation to express a suspicion, which is the same fabrication as any
  /// other confident wrong number, only pointing the safe way. What the
  /// mechanism DOES support is named in the note and left to the reader:
  ///   * SKIN TEMPERATURE. A charging pack is a heat source bonded to the strap
  ///     and the channel is relative-ADC with no absolute reference, so this
  ///     night's skin temp is not comparable to a night without one. That is a
  ///     per-CHANNEL caveat, and the honest fix is to withhold the night from
  ///     the skin-temp baseline rather than to fuzz the whole night's sleep —
  ///     which is a baseline-layer change, not this one.
  ///   * A MOTION BURST at each end. Clipping and unclipping the pack is a hand
  ///     movement on the instrumented wrist, so the stager will read wake there.
  ///     It is bounded, it is at a known timestamp, and it is real movement, so
  ///     it is reported rather than smoothed away.
  @visibleForTesting
  static Map<String, dynamic> sleepChargingBlock(
    List<List<int>> chargingSpans,
    int onsetSec,
    int offsetSec,
  ) {
    if (offsetSec <= onsetSec) return const {'present': false};
    final spans = <List<int>>[];
    var sec = 0;
    for (final c in chargingSpans) {
      if (c.length < 2) continue;
      final lo = math.max(c[0], onsetSec);
      final hi = math.min(c[1], offsetSec);
      if (hi <= lo) continue;
      spans.add([lo, hi]);
      sec += hi - lo;
    }
    if (spans.isEmpty) return const {'present': false};
    return {
      'present': true,
      'minutes': (sec / 60).round(),
      'spans': spans,
      'note':
          'the strap was charging for part of this night. it stayed on your '
          'wrist and kept recording, so heart rate and beat timing are '
          'measured as usual — but the pack warms the strap, so this night\'s '
          'skin temperature is not comparable to a night without it, and '
          'clipping the pack on and off registers as wrist movement.',
    };
  }

  static Map<String, dynamic> _sleepPeriods(
    int onsetSec,
    int offsetSec,
    List<Map<String, dynamic>>? naps, {
    int? mainTstMin,
    double? mainEfficiency,
  }) {
    final periods = <Map<String, dynamic>>[];
    // Null-if-any-component-unknown. Summing a null duration as 0 would print a
    // confident total that is short by exactly the part we could not measure —
    // and the hero tile divides it by need, so the "% of need" arc understates
    // too. An unknown component makes the SUM unknown.
    var totalAsleep = 0;
    var totalKnown = true;
    if (offsetSec > onsetSec) {
      periods.add({
        'is_main': true,
        'onset_ts': onsetSec,
        'wake_ts': offsetSec,
        // Null when staging did not produce a TST. The screen renders "—";
        // substituting the in-bed span would silently relabel time in bed as
        // time asleep, which is the same conflation this change removes.
        'duration_min': mainTstMin,
        'in_bed_min': (offsetSec - onsetSec) ~/ 60,
        'efficiency': ?mainEfficiency,
        // No hypnogram here on purpose: it lives in the isolate-1 bundle's
        // `series.hypnogram`, which this isolate does not receive. The read
        // seam attaches it (see `_daySleep`), where the whole bundle is in
        // hand. Passing it from here would only ever have written null.
      });
      if (mainTstMin != null) {
        totalAsleep += mainTstMin;
      } else {
        totalKnown = false;
      }
    }
    if (naps == null) {
      // Not judged. The day may hold any number of unmeasured naps, so no
      // total can be stated — the screen renders "—" rather than a confident
      // figure that silently omits them.
      totalKnown = false;
    } else {
      for (final nap in naps) {
        periods.add(nap);
        final d = (nap['duration_min'] as num?)?.toInt();
        if (d != null) {
          totalAsleep += d;
        } else {
          totalKnown = false;
        }
      }
    }
    return {
      'periods': periods,
      'total_asleep_min': totalKnown ? totalAsleep : null,
    };
  }

  /// Daytime naps via the analytics `detectNaps` — the ONLY nap source.
  ///
  /// Writes the `naps` block (per-nap epoch bounds + TST/TIB + confidence) and
  /// the `nap_min` scalar (total minutes ASLEEP) used by the Sleep Coach and
  /// Timeline, and returns period maps for [_sleepPeriods] so the Sleep-periods
  /// screen lists exactly the same naps the Timeline draws. There used to be a
  /// second, coarser nap notion in `_sleepPeriods` built from 20-min stillness
  /// runs; a private regression fixture made the two disagree and feed two
  /// different screens.
  ///
  /// ABSENT is not ZERO. When the detector cannot judge the day, `nap_min` is
  /// left UNWRITTEN rather than set to 0 — a written 0 is a claim that there
  /// were no naps, and it would also be picked up as a real value downstream.
  /// Returns NULL for that unjudged case and a (possibly empty) list when the
  /// day really was judged, so [_sleepPeriods] can make the same distinction
  /// instead of reading "no naps returned" as "no naps happened".
  /// The explicit "nap assessment unknown" envelope.
  ///
  /// Every abstention path must publish this, not just the detector's own
  /// `!m.present` branch. `_computeDayBlocks` starts from an EMPTY bundlePatch
  /// and `_attachNaps` is the only writer of `naps`, so a path that returns
  /// without writing leaves the key missing entirely — and "key absent" and
  /// "judged, value null" are then two different encodings of the same fact,
  /// distinguishable only by HOW the abstention happened. A reader that checks
  /// `bundle['naps']?['value'] == null` and one that checks
  /// `bundle.containsKey('naps')` would disagree.
  /// Abstention path that still honours what the USER logged.
  ///
  /// The detector abstains on exactly the days this feature exists for — strap
  /// off for part of the afternoon, a short record, a failure. Returning early
  /// there dropped every logged nap on the floor: no card to see, no minutes
  /// credited, and no way to delete the row the user had just created, while
  /// the edit kept force-re-deriving that day forever.
  ///
  /// A logged nap needs nothing from the detector — it carries its own absolute
  /// bounds — so it is published on its own. The day is still reported as
  /// unjudged when the user logged nothing, because that is what it is.
  static List<Map<String, dynamic>>? _napsWhenUnjudged(
    Map<String, dynamic> bundle,
    Map<String, dynamic>? scMap,
    List<NapEdit> napEdits,
    String note,
  ) {
    final merged = applyNapEdits(const [], napEdits);
    if (merged.isEmpty) {
      _writeUnknownNaps(bundle, note);
      return null;
    }
    bundle['naps'] = <String, dynamic>{
      'value': merged,
      'detected': null,
      'count': merged.length,
      // No detection confidence, because there was no detection.
      'confidence': null,
      // AUTH is the closed vocabulary's "directly measured / definitional",
      // which is what a self-report is: the user is not estimating that they
      // napped, they are stating it. An invented fifth tier would be a string
      // no reader knows how to rank.
      'tier': ana.Tier.auth,
      'inputs_used': const ['user'],
      'note': '$note — showing what you logged',
    };
    scMap?['nap_min'] = napMinutes(merged).toDouble();
    return [
      for (final nap in merged)
        {
          'is_main': false,
          'onset_ts': nap['start'],
          'wake_ts': nap['end'],
          'duration_min': nap['duration_min'],
          'in_bed_min': nap['in_bed_min'],
          'efficiency': null,
          'confidence': null,
          if (nap['source'] != null) 'source': nap['source'],
        },
    ];
  }

  static void _writeUnknownNaps(Map<String, dynamic> bundle, String note) {
    bundle['naps'] = <String, dynamic>{
      'value': null,
      'count': null,
      'confidence': 0,
      'tier': 'ESTIMATE',
      'inputs_used': const <String>[],
      'note': note,
    };
  }

  static List<Map<String, dynamic>>? _attachNaps(
    Map<String, dynamic> bundle,
    Map<String, dynamic>? scMap,
    Substrate s,
    int onsetSec,
    int offsetSec, {
    int? attributionStartSec,
    int? attributionEndSec,
    List<List<int>> wristOff = const [],
    List<List<int>> charging = const [],
    // Read on the main isolate and carried in, like every other DB-sourced
    // input here — this runs inside the compute worker, which has no database.
    List<NapEdit> napEdits = const [],
  }) {
    try {
      final n = s.length;
      if (n < 60) {
        return _napsWhenUnjudged(
          bundle,
          scMap,
          napEdits,
          'too little 1 Hz data to assess naps',
        );
      }
      final accel = <ana.AccelSample>[
        for (var i = 0; i < n; i++)
          ana.AccelSample(
            s.tsSec[i] * 1000.0,
            s.ax[i],
            s.ay[i],
            s.az[i],
            valid: s.accelPresentAt(i),
          ),
      ];
      final hr = [for (final h in s.hr) h.toDouble()];
      // Map the main-sleep epoch-second window to indices into the day arrays.
      ana.SleepWindowSpan? main;
      if (offsetSec > onsetSec) {
        var lo = -1, hi = -1;
        for (var i = 0; i < n; i++) {
          if (lo < 0 && s.tsSec[i] >= onsetSec) lo = i;
          if (s.tsSec[i] < offsetSec) hi = i + 1;
        }
        if (lo >= 0 && hi > lo) main = ana.SleepWindowSpan(lo, hi);
      }
      final m = ana.detectNaps(
        accel,
        hr,
        mainSleep: main,
        wristOff: wristOff,
        exclude: charging,
      );

      if (!m.present) {
        return _napsWhenUnjudged(
          bundle,
          scMap,
          napEdits,
          m.note ?? 'naps could not be assessed for this day',
        );
      }

      final t0 = s.tsSec.first;
      // The window opens AT local midnight and is contiguous into it, so a
      // bout [NapWindow.startsAtRecordEdge] flags — already in progress when
      // we started looking — is the tail of something that started
      // YESTERDAY, and yesterday's buffered window (which runs
      // `napBoundaryBufferSec` past its own midnight) saw it whole and
      // emitted it whole.
      //
      // analytics#40 (closing edge#204's workaround): this used to be
      // guessed from `nap.startSec == 0`, which only ever caught the FIRST
      // bout of the window — a bout chained onto it within `napChainGapSec`
      // (a brief arousal right at midnight) has `startSec > 0` but is just as
      // edge-anchored, and the old check let it through uncounted. Analytics
      // now propagates the flag through the whole chain (nap.dart), so
      // testing it directly instead of re-deriving it from the index catches
      // those fragments too.
      //
      // Still gated on contiguity, NOT on the flag alone: if the record only
      // STARTS hours into the day (band off overnight), yesterday's detector
      // broke on that same discontinuity and dropped the bout too, so
      // dropping it here as well would lose a real nap rather than
      // de-duplicate one.
      final leadingEdgeOwnedByYesterday =
          attributionStartSec != null &&
          t0 <= attributionStartSec + napLeadingEdgeContiguitySec;
      // A nap STARTING at/after the real day boundary is tomorrow's — its own
      // (unbuffered) window finds it independently, so keeping it here too
      // would double-count it.
      final naps = m.value!.where((nap) {
        if (leadingEdgeOwnedByYesterday && nap.startsAtRecordEdge) {
          return false;
        }
        if (attributionEndSec == null) return true;
        return t0 + nap.startSec < attributionEndSec;
      }).toList();

      // The detector's answer is a PROPOSAL. The user's edits — a nap it
      // missed, or one it invented — are stored separately and replayed over
      // it here on every derivation, so a better detector later still respects
      // "there was no nap here" instead of the edit being baked into a stale
      // detection.
      final detected = <Map<String, dynamic>>[
        for (final nap in naps)
          {
            'start': t0 + nap.startSec,
            'end': t0 + nap.endSec,
            // Minutes ASLEEP. `duration_min` kept as the asleep figure so
            // existing readers do not silently switch to in-bed minutes.
            'duration_min': (nap.tstSec / 60).round(),
            'in_bed_min': (nap.tibSec / 60).round(),
            'efficiency': nap.efficiency,
            'confidence': nap.confidence,
          },
      ];
      final merged = applyNapEdits(detected, napEdits);

      bundle['naps'] = <String, dynamic>{
        'value': merged,
        'detected': detected,
        'count': merged.length,
        'confidence': m.confidence,
        'tier': m.tier,
        'inputs_used': m.inputs_used,
        'note': napEdits.isEmpty ? m.note : '${m.note} (edited)',
      };

      // TST, never TIB. Crediting in-bed minutes against sleep need
      // over-credits every nap by its awake time and always errs toward
      // recommending LESS sleep than the user needs.
      // Rounded, matching the two display paths exactly. Truncating here while
      // the cards round made the credit disagree with the sum of the minutes
      // shown — up to a minute per nap, in a number the user can add up.
      // Summed over the MERGED list, so a logged nap counts toward sleep need
      // and sleep debt exactly as a detected one does.
      scMap?['nap_min'] = napMinutes(merged).toDouble();

      return [
        for (final nap in merged)
          {
            'is_main': false,
            'onset_ts': nap['start'],
            'wake_ts': nap['end'],
            'duration_min': nap['duration_min'],
            'in_bed_min': nap['in_bed_min'],
            'efficiency': nap['efficiency'],
            'confidence': nap['confidence'],
            if (nap['source'] != null) 'source': nap['source'],
          },
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('[derive] naps FAILED/skipped: $e');
      return _napsWhenUnjudged(
        bundle,
        scMap,
        napEdits,
        'nap detection failed for this day',
      );
    }
  }

  /// Runs [_computeDayBlocks] in an explicitly spawned, killable isolate and
  /// enforces [timeout] on the isolate itself — not just on the caller's wait.
  ///
  /// `Isolate.run(...).timeout(...)` (the previous approach) only stops the
  /// CALLER from awaiting the result; the spawned isolate keeps executing to
  /// completion in the background regardless. Under a multi-day backlog with
  /// a bounded worker pool ([_deriveConcurrency]), a slow/hung day's abandoned
  /// isolate can keep burning CPU well after its caller moved on to the next
  /// day — silently exceeding the intended concurrency budget. Spawning the
  /// isolate ourselves gives us a handle to actually `kill()` it on timeout.
  static Future<_DayBlocksOutput> _runDayBlocksCancellable(
    _DayBlocksInput input,
    Duration timeout,
  ) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      _dayBlocksIsolateEntry,
      (port.sendPort, input),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final completer = Completer<_DayBlocksOutput>();
    final stop = DeriveStop.changes.listen((_) {
      if (completer.isCompleted) return;
      isolate.kill(priority: Isolate.immediate);
      completer.completeError(DeriveStop.error);
    });
    late final StreamSubscription<dynamic> sub;
    sub = port.listen((message) {
      if (completer.isCompleted) return;
      if (message is _DayBlocksOutput) {
        completer.complete(message);
      } else if (message is List) {
        // Either our own caught-exception report (`[error, stack]`) or the
        // `onError` port's uncaught-error format — both are 2-element lists
        // of strings. `onExit` fires with `null`, which we treat as "the
        // isolate ended without ever sending a result" below.
        completer.completeError(
          StateError(
            message.isNotEmpty
                ? 'day-blocks isolate failed: ${message.first}'
                : 'day-blocks isolate failed with no error detail',
          ),
        );
      } else if (message == null) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('day-blocks isolate exited without a result'),
          );
        }
      }
    });
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          isolate.kill(priority: Isolate.immediate);
          throw TimeoutException(
            'day-blocks computation timed out after $timeout',
          );
        },
      );
    } finally {
      await stop.cancel();
      await sub.cancel();
      port.close();
      // No-op if the isolate already exited normally; guarantees a hung or
      // still-running isolate never outlives this call.
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Run [compute] in an explicitly spawned isolate and enforce [timeout] ON THE
  /// ISOLATE — the general-purpose form of [_runDayBlocksCancellable].
  ///
  /// `Isolate.run(...).timeout(...)` only stops the CALLER awaiting; the spawned
  /// isolate keeps burning CPU to completion in the background. With a bounded
  /// per-day worker pool that silently blows the concurrency budget during a
  /// backlog sweep — which is exactly why [_runDayBlocksCancellable] exists, and
  /// it had been applied to only one of the file's isolate sites. Worse, some
  /// sites (the sleep-staging pass) had NO timeout at all, so a hung isolate
  /// wedged the engine with `_running == true` forever.
  ///
  /// Also wires `onError`/`onExit` so an uncaught throw or a silent death
  /// FAILS the future instead of hanging it.
  static Future<R> _runIsolateCancellable<R>(
    FutureOr<R> Function() compute,
    Duration timeout, {
    required String label,
  }) async {
    final port = ReceivePort();
    final (SendPort, FutureOr<Object?> Function()) message = (
      port.sendPort,
      compute,
    );
    final isolate = await Isolate.spawn(
      _cancellableIsolateEntry,
      message,
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final completer = Completer<R>();
    final stop = DeriveStop.changes.listen((_) {
      if (completer.isCompleted) return;
      isolate.kill(priority: Isolate.immediate);
      completer.completeError(DeriveStop.error);
    });
    late final StreamSubscription<dynamic> sub;
    sub = port.listen((msg) {
      if (completer.isCompleted) return;
      if (msg is _IsolateValue) {
        completer.complete(msg.value as R);
      } else if (msg is List) {
        // Our caught-exception report or the `onError` port's uncaught-error
        // format — both 2-element lists of strings.
        completer.completeError(
          StateError(
            msg.isNotEmpty
                ? '$label isolate failed: ${msg.first}'
                : '$label isolate failed with no error detail',
          ),
        );
      } else if (msg == null) {
        // `onExit` — the isolate ended without ever sending a result.
        completer.completeError(
          StateError('$label isolate exited without a result'),
        );
      }
    });
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          isolate.kill(priority: Isolate.immediate);
          throw TimeoutException('$label timed out after $timeout');
        },
      );
    } finally {
      await stop.cancel();
      await sub.cancel();
      port.close();
      // No-op if it already exited; guarantees a hung isolate never outlives
      // this call.
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// `Isolate.spawn` entry point for [_runIsolateCancellable].
  static Future<void> _cancellableIsolateEntry(
    (SendPort, FutureOr<Object?> Function()) args,
  ) async {
    final (sendPort, compute) = args;
    try {
      sendPort.send(_IsolateValue(await compute()));
    } catch (e, st) {
      sendPort.send([e.toString(), st.toString()]);
    }
  }

  /// `Isolate.spawn` entry point for [_runDayBlocksCancellable]. Must be a
  /// static/top-level function taking exactly one (sendable) argument.
  static void _dayBlocksIsolateEntry((SendPort, _DayBlocksInput) args) {
    final (sendPort, input) = args;
    try {
      sendPort.send(_computeDayBlocks(input));
    } catch (e, st) {
      sendPort.send([e.toString(), st.toString()]);
    }
  }

  /// The full PURE second half of per-day derivation, run OFF the calling
  /// isolate via a cancellable spawned isolate (see [_runDayBlocksCancellable],
  /// [_derivePreparedDay]). Previously ALL of this ran on whatever isolate
  /// drove the engine — the UI isolate for the foreground light pass fired on
  /// every sync — producing multi-second main-thread hangs (rolling RSA
  /// Lomb-Scargle over the 24 h day, nap re-staging, workout detection, wake
  /// features, steps/energy). DB reads are performed by the caller and passed
  /// in; DB writes + notifications are returned as descriptors for the caller
  /// to apply.
  static _DayBlocksOutput _computeDayBlocks(_DayBlocksInput inp) {
    DayClock.restore(inp.dayContext);
    final daySub = inp.daySub;
    final sleepSub = inp.sleepSub;
    final onset = inp.onsetSec;
    final offset = inp.offsetSec;
    final bundlePatch = <String, dynamic>{};
    final seriesPatch = <String, dynamic>{};
    // Working scalars — everything computed below is written here and merged
    // back by the caller. It used to be seeded with `{'rhr': inp.rhr}` under a
    // comment claiming the pure helpers read it; nothing does (they take
    // `restingHr` as an argument), and the seed then had to be deleted again
    // before returning. `inp.rhr` is the NOCTURNAL resting HR, never the
    // daytime fallback — see `_DayBlocksInput.rhr`.
    final scMap = <String, dynamic>{};

    final wake = applyDayActivity(
      bundle: bundlePatch,
      scalars: scMap,
      daySub: daySub,
      profile: inp.profile,
      sleepOnsetSec: onset,
      sleepOffsetSec: offset,
      dayStartSec: inp.dayStartSec,
      // NOT `inp.dayEndSec` — that is the data edge. See `applyDayActivity`.
      dayCalendarEndSec: localNextMidnightSecForDayLabel(inp.date),
      dataNowSec: inp.dataNowSec,
      viewNowSec: inp.viewNowSec,
      wristOff: inp.wristOffSpans,
      charging: inp.chargingSpans,
      restingHr: inp.rhr,
      dynFloorG: inp.dynFloorG,
      liveStepsReal: inp.liveStepsReal,
      liveStepsFromStrap: inp.liveStepsFromStrap,
      dynHistoryDays: inp.dynHistoryDays,
      stepSpans: inp.stepSpans,
      sessions: inp.savedSessions,
      zoneSet: inp.zoneSet,
    );

    bundlePatch['day_zone'] = DayClock.forDate(inp.date)?.toRow();
    bundlePatch['sleep_spans_zone_change'] = DayClock.spansZoneChange(
      onset,
      offset,
    );
    bundlePatch['sleep_onset_local_min'] = onset > 0
        ? DayClock.localAt(onset).hour * 60 + DayClock.localAt(onset).minute
        : null;
    bundlePatch['sleep_wake_local_min'] = offset > 0
        ? DayClock.localAt(offset).hour * 60 + DayClock.localAt(offset).minute
        : null;
    bundlePatch['daytime_hrv'] = _daytimeHrv(daySub, onset, offset);
    seriesPatch['hrv_day'] = dayHrvCurve(daySub);
    seriesPatch['resp_day'] = dayRespCurve(daySub);
    seriesPatch['skin_temp_day'] = _daySkinTempCurve(daySub);
    bundlePatch['restlessness'] = _restlessness(sleepSub);
    // napSub extends a few hours past this day's calendar end so a nap/
    // secondary-sleep block spanning midnight isn't bisected — but a run that
    // actually STARTS in that borrowed buffer belongs to tomorrow (which sees
    // it in its own regular window), so both helpers drop anything starting
    // at/after dayEndSec to avoid double-counting.
    // Naps FIRST — `_sleepPeriods` lists exactly these, so the Timeline bands
    // and the Sleep-periods cards can never disagree again.
    final napPeriods = _attachNaps(
      bundlePatch,
      scMap,
      inp.napSub,
      onset,
      offset,
      attributionStartSec: inp.dayStartSec,
      attributionEndSec: inp.dayEndSec,
      wristOff: inp.wristOffSpans,
      charging: inp.chargingSpans,
      napEdits: inp.napEdits,
    );
    bundlePatch['sleep_periods'] = _sleepPeriods(
      onset,
      offset,
      napPeriods,
      mainTstMin: inp.mainTstMin,
      mainEfficiency: inp.mainEfficiency,
    );
    bundlePatch['sleep_charging'] = sleepChargingBlock(
      inp.chargingSpans,
      onset,
      offset,
    );
    // Overrides wake's activity_curve (same value, computed once here).
    bundlePatch['activity_curve'] = _activityCurve(daySub);
    // `detected_workouts` is NOT written. It was a permanently-empty stub kept
    // for a WorkoutDetector pass that was going to be re-homed here; analytics
    // has since deleted `workout_detect.dart`, so there is no pass to re-home
    // and no reason to write an empty list every day. The repository's reader
    // already skips a missing key, and auto-detected bouts reach the UI through
    // `workout_suggestions` below.

    final wc = _computeWorkouts(
      s: daySub,
      maxHr: inp.maxHrUsed,
      rhrScalar: inp.rhr,
      saved: inp.savedSessions,
      date: inp.date,
      dayEndSec: inp.dayEndSec,
      dataNowSec: inp.dataNowSec,
    );
    bundlePatch['workout_suggestions'] = wc.boutJson;
    if (wc.hrrBpm != null) scMap['hrr_bpm'] = wc.hrrBpm;
    if (wc.hrrTauS != null) scMap['hrr_tau_s'] = wc.hrrTauS;
    final ceiling = _dayHrCeiling(daySub, inp.savedSessions);
    bundlePatch['hr_ceiling'] = ceiling;
    // TS-03 — the day's observed ceiling as a SCALAR too, so the app-wide
    // "highest we've seen" is a max over `metric_series` (one small query the
    // baseline cache already loads) instead of a scan of every stored bundle.
    // The envelope above keeps the date/session/hold the copy needs; this is
    // just the number, and only when the day actually held one.
    // `Metric.toJson` writes the STRING '—' for an absent value, not null, so
    // this must type-test rather than cast.
    final ceilingValue = ceiling['value'];
    if (ceilingValue is Map && ceilingValue['bpm'] is num) {
      scMap['hr_ceiling_bpm'] = (ceilingValue['bpm'] as num).toDouble();
    }

    _attachWristOrientation(bundlePatch, daySub, onset, offset);
    bundlePatch['advanced_sleep'] = const {'present': false};

    // Arm-angle range, not uncalibrated magnitude-minus-1 g. Existing
    // relative-stillness breathing qualification is a separate concern.
    final angleMap = ana.armAngleRestlessness(sleepSub.accelSamples());
    if (angleMap.isNotEmpty) bundlePatch['restlessness_map'] = angleMap;

    // Feature 2 (fit-quality diagnostic) is GONE, not disabled. It scored band
    // tightness from `skinContact`, and there is no contact-quality field to
    // score: the byte is the sign+exponent half of a float32, which is why its
    // only observed values are {0, 63-70, 194-198}. On the decoded path it was
    // additionally a hardcoded 0 (`decoded_onehz` has no such column), so the
    // gate could never fire. A diagnostic built on a non-measurement is worse
    // than no diagnostic.

    return _DayBlocksOutput(
      bundlePatch: bundlePatch,
      seriesPatch: seriesPatch,
      scalarPatch: scMap,
      wake: wake,
      suggestionsToPersist: wc.suggestionsToPersist,
      sessionHrrWrites: wc.sessionHrrWrites,
      notifBout: wc.notifBout,
    );
  }

  /// PURE compute half of workout SUGGESTIONS (`autoDetectWorkouts`) + HRR.
  ///
  /// Runs inside the day-blocks isolate: one detector pass over the day's 1 Hz HR
  /// (+ gravity motion) yields the detected bouts (excluding any already-saved
  /// manual/live session, passed in via [saved] which the caller read from the DB
  /// on the DB-owning isolate) and each bout's HR-tail HRR-60s drop. Returns the
  /// bout JSON, the mean `hrr_bpm`, the retrospective per-session HRR writes, the
  /// recent-day suggestions to persist, and the freshly-ended notif candidate —
  /// the DB writes + notification are performed by the caller on the main isolate.
  static _WorkoutCompute _computeWorkouts({
    required Substrate s,
    required int? maxHr,
    required double? rhrScalar,
    required List<Map<String, dynamic>> saved,
    required String date,
    required int dayEndSec,
    required int dataNowSec,
  }) {
    try {
      final n = s.length;
      if (n < 60) return const _WorkoutCompute.empty();
      final hrTs = <int>[];
      final hrBpm = <int>[];
      for (var i = 0; i < n; i++) {
        if (s.hr[i] > 0) {
          hrTs.add(s.tsSec[i]);
          hrBpm.add(s.hr[i]);
        }
      }
      if (hrBpm.length < 60) return const _WorkoutCompute.empty();
      // Feed the detector only the seconds that carry a real gravity vector.
      // Absent accel reads as a motionless wrist, which is exactly the shape
      // that suppresses a workout candidate — a missed workout, silently.
      final mTs = <int>[], mAx = <double>[], mAy = <double>[], mAz = <double>[];
      for (var i = 0; i < n; i++) {
        if (!s.accelPresentAt(i)) continue;
        mTs.add(s.tsSec[i]);
        mAx.add(s.ax[i]);
        mAy.add(s.ay[i]);
        mAz.add(s.az[i]);
      }
      final motion = ana.AutoWorkoutDetector.motionPoints(mTs, mAx, mAy, mAz);
      // Exclude windows the user has already logged (manual/live wins).
      final savedSpans = <ana.SavedWorkoutSpan>[
        for (final r in saved)
          if (r['start_ts'] is int && r['end_ts'] is int)
            ana.SavedWorkoutSpan(r['start_ts'] as int, r['end_ts'] as int)
          // Build 90: a workout still running has no end yet; it covers
          // everything from its start up to the data edge, so its own effort
          // is never offered back as "spotted but not logged".
          else if (r['start_ts'] is int && r['end_ts'] == null)
            ana.SavedWorkoutSpan(
              r['start_ts'] as int,
              math.max(r['start_ts'] as int, dataNowSec),
            ),
      ];
      final rhr = rhrScalar?.round();
      // Auto-detection needs a real resting-HR baseline. Without one the detector
      // can't compute a trustworthy %HRR floor and ordinary daytime HR reads as a
      // workout. If we don't have a nightly RHR for this day yet, skip detection
      // entirely (HRR for already-saved sessions below still runs).
      final bouts = rhr == null
          ? const <ana.DetectedWorkout>[]
          : (ana
                    .autoDetectWorkouts(
                      hrTs: hrTs,
                      hrBpm: hrBpm,
                      restingBpm: rhr,
                      maxBpm: maxHr,
                      motion: motion,
                      savedSpans: savedSpans,
                    )
                    .value ??
                const <ana.DetectedWorkout>[]);

      // HRR per bout from the per-second HR tail bracketing each bout end.
      final drops = <double>[];
      final taus = <double>[];
      final boutJson = <Map<String, dynamic>>[];
      for (final b in bouts) {
        final r = _hrrForBout(s, b.endSec);
        final m = r.hrrBpm;
        if (m != null) drops.add(m);
        if (r.tauSec != null) taus.add(r.tauSec!);
        boutJson.add({
          'start': b.startSec,
          'end': b.endSec,
          'avg_bpm': b.avgBpm,
          'peak_bpm': b.peakBpm,
          'duration_min': b.durationMin,
          'sport': b.sport,
          if (m != null) 'hrr_bpm': double.parse(m.toStringAsFixed(1)),
          if (r.tauSec != null) 'hrr_tau_s': r.tauSec!.round(),
        });
      }
      // Also fill HRR for already-saved sessions (manual/live) retrospectively
      // from the substrate around each session's end — so the workout detail
      // screen shows HRR without buffering 60 s after a live stop.
      final sessionHrr = <(String, double)>[];
      for (final r in saved) {
        final id = r['id'];
        final endTs = r['end_ts'];
        if (id is! String || endTs is! int) continue;
        final rec = _hrrForBout(s, endTs);
        final m = rec.hrrBpm;
        if (rec.tauSec != null) taus.add(rec.tauSec!);
        if (m != null) {
          drops.add(m);
          sessionHrr.add((id, double.parse(m.toStringAsFixed(1))));
        }
      }
      final hrrBpm = drops.isEmpty
          ? null
          : double.parse(
              (drops.reduce((a, c) => a + c) / drops.length).toStringAsFixed(1),
            );
      // Mean tau over the bouts that SURVIVED the residual gate — deliberately
      // a different denominator from `hrrBpm`'s, because the gate abstains
      // often and pretending otherwise would average a fit never made.
      final hrrTauS = taus.isEmpty
          ? null
          : double.parse(
              (taus.reduce((a, c) => a + c) / taus.length).toStringAsFixed(1),
            );

      // Persist + notify only for RECENT days (≤ ~36 h old) so imports/re-analyze
      // don't resurface 90 days of prompts.
      final recent = (dataNowSec - dayEndSec) < 36 * 3600;
      final toPersist = <Map<String, dynamic>>[];
      ({String id, int durationMin})? notif;
      // ONE definition of the row id. The notification checks the table by it
      // and opens the screen on it, so a second copy of the format here would
      // drift into a prompt that silently never fires again.
      String sugId(int startSec) => '$date:$startSec';
      if (recent && bouts.isNotEmpty) {
        for (final b in bouts) {
          toPersist.add({
            'id': sugId(b.startSec),
            'date': date,
            'start_ts': b.startSec,
            'end_ts': b.endSec,
            'avg_bpm': b.avgBpm,
            'peak_bpm': b.peakBpm,
            'duration_min': b.durationMin,
            'sport': b.sport,
            'dismissed': 0,
          });
        }
        // Notify ONLY for a bout that ended in the last ~2 h (a near-real-time
        // detection). Draining a backlog (e.g. an overnight gap) re-derives a whole
        // day at once; without this every hours-old bout would fire a "did you work
        // out?" prompt → a wall of notifications. Suggestions are still persisted
        // above so they surface in the Workouts screen; we just don't ping for them.
        final newest = bouts.reduce((a, b) => a.endSec >= b.endSec ? a : b);
        if ((dataNowSec - newest.endSec) < 2 * 3600) {
          notif = (id: sugId(newest.startSec), durationMin: newest.durationMin);
        }
      }
      return _WorkoutCompute(
        boutJson: boutJson,
        hrrBpm: hrrBpm,
        hrrTauS: hrrTauS,
        sessionHrrWrites: sessionHrr,
        suggestionsToPersist: toPersist,
        notifBout: notif,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[derive] auto-workout/HRR FAILED/skipped: $e');
      }
      return const _WorkoutCompute.empty();
    }
  }

  /// TS-03 — the day's OBSERVED heart-rate ceiling: the highest bpm any of this
  /// day's SAVED sessions held for ≥15 continuous seconds with corroborating
  /// motion, tagged with the session it came from.
  ///
  /// NOT a physiological HRmax and not a substitute for one. Whoever renders it
  /// says "highest we've seen: 184, on 3 Aug" with the date and the session,
  /// never "your max HR is 184", and never invites a max-effort test. The
  /// app-wide ceiling is the max over days of the PRESENT values — a one-line
  /// reduce for the reader, deliberately not a second function here, so the
  /// hold+motion guard cannot be bypassed by reducing over un-guarded numbers.
  ///
  /// Absent is the common case and it is correct: most sessions do not test
  /// your ceiling. So is an unknown device family — the motion gate is a
  /// property of the sensor package and gen4's floor is not a default (see
  /// `observed_max_hr.dart`).
  ///
  /// Sessions are scored ONE AT A TIME, never as a concatenated day: a hold
  /// must be continuous inside one session, and stitching two sessions would
  /// invent a hold across the gap between them.
  @visibleForTesting
  static Map<String, dynamic> dayHrCeiling(
    Substrate s,
    List<Map<String, dynamic>> saved,
  ) => _dayHrCeiling(s, saved);

  static Map<String, dynamic> _dayHrCeiling(
    Substrate s,
    List<Map<String, dynamic>> saved,
  ) {
    ana.Metric<ana.HrCeiling>? best;
    String? bestId;
    String? bestType;
    ana.Metric<ana.HrCeiling>? lastAbsent;
    for (final row in saved) {
      final start = (row['start_ts'] as num?)?.toInt();
      final end = (row['end_ts'] as num?)?.toInt();
      if (start == null || end == null || end <= start) continue;
      final hr = <ana.HrSample>[];
      final accel = <ana.AccelSample>[];
      for (var i = 0; i < s.length; i++) {
        final t = s.tsSec[i];
        if (t < start) continue;
        if (t > end) break;
        final tsMs = t * 1000.0;
        hr.add(ana.HrSample(tsMs, s.hr[i].toDouble()));
        accel.add(
          ana.AccelSample(
            tsMs,
            s.ax[i],
            s.ay[i],
            s.az[i],
            valid: s.accelPresentAt(i),
          ),
        );
      }
      if (hr.isEmpty) continue;
      final m = ana.sessionHrCeiling(hr, accel, deviceFamily: s.deviceFamily);
      if (!m.present) {
        lastAbsent = m;
        continue;
      }
      if (best == null || m.value!.bpm > best.value!.bpm) {
        best = m;
        bestId = row['id']?.toString();
        bestType = row['type']?.toString();
      }
    }
    final m =
        best ??
        lastAbsent ??
        const ana.Metric<ana.HrCeiling>.absent(
          tier: ana.Tier.high,
          inputs_used: ['hr_1hz', 'accel_1hz', 'device_family'],
          note: 'no saved session on this day to observe a ceiling in',
        );
    return {
      ...m.toJson((v) => v.toJson()),
      'session_id': ?bestId,
      'session_type': ?bestType,
    };
  }

  /// HRR-60s + the recovery time constant for a bout ending at [endSec]: build
  /// the per-second HR tail around the end index, delegate the drop to
  /// [ana.hrRecovery] and fit tau over the same tail. Either half may be null.
  static ({double? hrrBpm, double? tauSec}) _hrrForBout(
    Substrate s,
    int endSec,
  ) {
    const none = (hrrBpm: null, tauSec: null);
    final n = s.length;
    if (n == 0) return none;
    // Find the index nearest the bout end.
    var endIdx = -1;
    for (var i = 0; i < n; i++) {
      if (s.tsSec[i] >= endSec) {
        endIdx = i;
        break;
      }
    }
    if (endIdx < 0) endIdx = n - 1;
    // SLICE BY TIME, not by array position. The substrate is one row per
    // DECODED RECORD, not a dense 1 Hz grid, so `endIdx ± 30/75` used to cut a
    // window whose real duration depended on how gappy the tail was: on a sparse
    // day it stopped well short of +60 s (no recovery sample — HRR silently
    // absent), on a dense one it reached far past it. The comment below already
    // said this about `hrRecovery`'s own +60 s; the slice feeding it never
    // followed. ±30/+75 SECONDS around the bout end, so the 60-second sample is
    // always inside the window when the data exists at all.
    // +180 s, not +75: HRR-60 only ever needed to reach the 60-second sample,
    // but tau is fitted over the whole decay and a 75-second tail is one time
    // constant of curve. Widening does NOT move `hrr_bpm` — `hrRecovery` locates
    // its recovery point on the CLOCK and stops at the first sample past +60 s.
    const preSec = 30, postSec = 180;
    var lo = endIdx;
    while (lo > 0 && s.tsSec[lo - 1] >= endSec - preSec) {
      lo--;
    }
    var hi = endIdx;
    while (hi + 1 < n && s.tsSec[hi + 1] <= endSec + postSec) {
      hi++;
    }
    final tail = <int>[for (var i = lo; i <= hi; i++) s.hr[i]];
    // `hrRecovery` reads "+60 s" off `tsSec`, not off the array index — on a
    // gappy tail the recovery sample would otherwise be many minutes
    // post-exercise and the drop is overstated, read by the user as a fitness
    // marker.
    final tailTs = <int>[for (var i = lo; i <= hi; i++) s.tsSec[i]];
    final m = ana.hrRecovery(
      tail,
      endIndex: endIdx - lo,
      recoverySec: 60,
      tsSec: tailTs,
    );
    // B88-03: ONE tau — the analytics library's, fitted in the same call.
    // The app used to fit its own and discard the library's.
    return (
      hrrBpm: m.present ? m.value!.dropBpm : null,
      tauSec: m.present ? m.value!.tauSec : null,
    );
  }

  /// Recovery time constant (s): the analytics library's monoexponential fit
  /// ([ana.hrRecovery]'s `tauSec`), the one source since B88-03. Published
  /// alongside HRR-60, never instead of it; null when the fit's gates abstain.
  @visibleForTesting
  static double? recoveryTau(List<int> hr, List<int> tsSec, int endIdx) {
    final m = ana.hrRecovery(
      hr,
      endIndex: endIdx,
      recoverySec: 60,
      tsSec: tsSec,
    );
    return m.present ? m.value!.tauSec : null;
  }

  /// Low-confidence WRIST ORIENTATION during the sleep window (`positionSeries`).
  /// Explicitly a WRIST measure (body-position PROXY), never claimed as the
  /// sleeper's supine/side/prone body position. Emits a dominant-orientation
  /// summary + per-position minutes + an orientation-change count. Best-effort.
  static void _attachWristOrientation(
    Map<String, dynamic> bundle,
    Substrate s,
    int onsetSec,
    int offsetSec,
  ) {
    try {
      if (offsetSec <= onsetSec) return;
      final epoch = <ana.AccelSample>[
        for (var i = 0; i < s.length; i++)
          if (s.tsSec[i] >= onsetSec && s.tsSec[i] < offsetSec)
            ana.AccelSample(
              s.tsSec[i] * 1000.0,
              s.ax[i],
              s.ay[i],
              s.az[i],
              valid: s.accelPresentAt(i),
            ),
      ];
      if (epoch.length < 60) return;
      final tilts = ana.positionSeries(epoch, epochSec: 30);
      if (tilts.isEmpty) return;
      // Per-position minutes (each epoch ≈ 30 s) + orientation-change count.
      final mins = <String, double>{};
      var changes = 0;
      String? prev;
      for (final t in tilts) {
        mins[t.position] = (mins[t.position] ?? 0) + 0.5; // 30 s
        if (prev != null && prev != t.position) changes++;
        prev = t.position;
      }
      String dominant = 'unknown';
      var best = -1.0;
      mins.forEach((k, v) {
        if (v > best) {
          best = v;
          dominant = k;
        }
      });
      bundle['wrist_orientation'] = <String, dynamic>{
        'dominant': dominant,
        'minutes': mins,
        'changes': changes,
        'epochs': tilts.length,
        'confidence': 'low',
        'tier': ana.Tier.relative,
        'note':
            'WRIST orientation during sleep (gravity-tilt). A body-position '
            'PROXY, NOT supine/side/prone body position — the wrist moves '
            'independently of the torso.',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[derive] wrist-orientation FAILED/skipped: $e');
      }
    }
  }

  // static: pure day-label arithmetic, and `rawPruneCutoffSec` needs it.
  static int _localDayLabelToSec(String day) => localDayStartSec(day) ?? 0;
  int _localNextDayLabelToSec(String day) => localDayEndSec(day) ?? 0;

  String _skipReasonForError(Object error) {
    final msg = error.toString();
    if (msg.contains('day_prepare_budget_exceeded')) {
      return 'day_prepare_budget_exceeded';
    }
    if (msg.contains('TimeoutException')) {
      return 'timeout';
    }
    return 'error';
  }

  /// The substrate range to LOAD so [calendarDays] can actually run its
  /// documented nocturnal search for [dayId].
  ///
  /// `calendarDays` searches from the previous local NOON
  /// (`dayStart − kNocturnalSearchLookbackSec`), and its comment records that
  /// widening from the old prev-18:00 window as deliberate — "the old
  /// prev-18:00 → noon window missed late wakes and forced the detector to act
  /// like there was only one candidate sleep". But this loader only fetched
  /// `dayStart − 6 h` (= 18:00), and `searchStart = math.max(dataStart, …)`
  /// clipped the search right back to the slice start, so the widening was a
  /// no-op and any sleep onset before 18:00 was truncated. Load the whole
  /// window the day model asks for, from the one shared constant.
  (int, int) _targetDayWindow(String dayId) {
    final startSec = _localDayLabelToSec(dayId);
    final endSec = _localNextDayLabelToSec(dayId);
    return (math.max(0, startSec - kNocturnalSearchLookbackSec), endSec - 1);
  }

  /// Test seam for [_targetDayWindow] — the bug was that this loader and
  /// [calendarDays]' search window silently disagreed, so the agreement is
  /// pinned directly.
  @visibleForTesting
  (int, int) debugTargetDayWindow(String dayId) => _targetDayWindow(dayId);

  /// Test seam for [_sleepPeriods] — "an unjudged day publishes no total" is a
  /// one-line invariant guarding a user-visible number, so it is pinned
  /// directly rather than through a full derive pass.
  @visibleForTesting
  static Map<String, dynamic> debugSleepPeriods(
    int onsetSec,
    int offsetSec,
    List<Map<String, dynamic>>? naps, {
    int? mainTstMin,
    double? mainEfficiency,
  }) => _sleepPeriods(
    onsetSec,
    offsetSec,
    naps,
    mainTstMin: mainTstMin,
    mainEfficiency: mainEfficiency,
  );

  /// Test seam for [_attachNaps] — the day-boundary attribution rules (drop
  /// tomorrow's leading nap, drop yesterday's trailing one) decide which day a
  /// nap's minutes are credited to, and are cheap to state directly.
  @visibleForTesting
  static List<Map<String, dynamic>>? debugAttachNaps(
    Map<String, dynamic> bundle,
    Map<String, dynamic>? scMap,
    Substrate s,
    int onsetSec,
    int offsetSec, {
    int? attributionStartSec,
    int? attributionEndSec,
    List<List<int>> wristOff = const [],
    List<List<int>> charging = const [],
    List<NapEdit> napEdits = const [],
  }) => _attachNaps(
    bundle,
    scMap,
    s,
    onsetSec,
    offsetSec,
    attributionStartSec: attributionStartSec,
    attributionEndSec: attributionEndSec,
    wristOff: wristOff,
    charging: charging,
    napEdits: napEdits,
  );

  void _log(String m) {
    if (kDebugMode) debugPrint('[derive] $m');
    log?.call('[derive] $m');
  }
}

/// Wrapper for a cancellable-isolate result, so a computation whose OWN result
/// happens to be a `List` (the uncaught-error wire format) or `null` (the
/// `onExit` signal) can never be misread as a failure.
class _IsolateValue {
  final Object? value;
  const _IsolateValue(this.value);
}

/// Test seam for [DerivationEngine._runIsolateCancellable] — the isolate
/// lifecycle guarantees (value / error / killed-on-timeout) are what the engine
/// depends on to never hang, so they're pinned directly.
@visibleForTesting
Future<R> runCancellableIsolate<R>(
  FutureOr<R> Function() compute,
  Duration timeout, {
  String label = 'test',
}) => DerivationEngine._runIsolateCancellable(compute, timeout, label: label);

/// Sendable input for [DerivationEngine._computeDayBlocks] — crosses the
/// `Isolate.run` boundary, so every field is plain data (Substrate is int/double
/// lists; Profile is a primitive data class). DB reads that the
/// pure compute needs are performed by the caller and passed in here.
class _DayBlocksInput {
  final Substrate daySub;
  final Substrate napSub;
  final Substrate sleepSub;
  final Profile profile;
  final int onsetSec;
  final int offsetSec;

  /// NOCTURNAL resting HR for this day (`scalars.rhr_nocturnal`) — null unless a
  /// sleep session was detected. NOT `scalars.rhr`, which is allowed to fall
  /// back to daytime HR for the resting-HR card and is not a TRIMP reference.
  final double? rhr;
  final int? maxHrUsed;

  /// The pipeline's zone set ([trainingZones]), or null to fall back to the
  /// age estimate. See the construction site.
  final ana.HeartRateZoneSet? zoneSet;
  final int liveStepsReal;

  /// How much of [liveStepsReal] the BAND's own 100 Hz pedometer was credited
  /// with after the per-window resolution; the rest is the phone's. Carried so
  /// the bundle can say which sensor counted without re-reading the DB from the
  /// isolate, which has no handle.
  final int liveStepsFromStrap;

  /// The SAME resolution's credited spans, as `[startSec, endSec, steps]` —
  /// the walking-cadence energy term prices wake minutes off these (see
  /// `cadenceSpmForMinutes`). Credited, never raw rows, so a step the ladder
  /// took back off a span cannot be priced here either.
  final List<List<int>> stepSpans;

  /// PERSONAL ambulatory floor (g, dynAmp units) from trailing days, or null
  /// when there isn't enough history yet — in which case the 1 Hz estimator
  /// abstains rather than falling back to a constant. Computed on the main
  /// isolate (it needs metric_series) and carried in, like the other history.
  final double? dynFloorG;

  /// How many trailing days backed [dynFloorG] — only for the cold-start note.
  final int dynHistoryDays;

  final List<Map<String, dynamic>> savedSessions;

  /// The user's nap edits for this day, replayed over the detector's output.
  final List<NapEdit> napEdits;

  /// Strap-reported off-wrist spans ([startSec, endSec]) over the nap window.
  /// A band on a table is motionless and reads as deep rest — this is the
  /// dominant nap false positive, and the strap already tells us about it.
  final List<List<int>> wristOffSpans;

  /// Strap-reported charging spans — off-wrist by definition, and motionless.
  final List<List<int>> chargingSpans;

  /// Main-sleep TST (minutes) and efficiency (0..1) from ISOLATE 1.
  ///
  /// Carried explicitly because `_computeDayBlocks` builds its own fresh
  /// `scMap` seeded with `rhr` alone — reading `scMap['tst_min']` in there
  /// silently yields null forever, which is how the main sleep period came to
  /// report "—" for its duration.
  final int? mainTstMin;
  final double? mainEfficiency;

  final String date;

  /// Local midnight opening this calendar day — where `napSub` starts. Nap
  /// attribution needs BOTH boundaries: [dayEndSec] pushes a nap starting in
  /// the borrowed buffer onto tomorrow, and this one drops the tail of a nap
  /// yesterday already owns. See `_attachNaps`.
  final int dayStartSec;
  final int dayEndSec;
  final int dataNowSec;
  final int viewNowSec;
  final Map<String, dynamic> dayContext;
  const _DayBlocksInput({
    required this.daySub,
    required this.napSub,
    required this.sleepSub,
    required this.profile,
    required this.onsetSec,
    required this.offsetSec,
    required this.rhr,
    required this.maxHrUsed,
    this.zoneSet,
    required this.liveStepsReal,
    this.liveStepsFromStrap = 0,
    this.stepSpans = const [],
    required this.dynFloorG,
    required this.dynHistoryDays,
    required this.savedSessions,
    this.napEdits = const [],
    required this.wristOffSpans,
    required this.chargingSpans,
    required this.mainTstMin,
    required this.mainEfficiency,
    required this.date,
    required this.dayStartSec,
    required this.dayEndSec,
    required this.dataNowSec,
    required this.viewNowSec,
    required this.dayContext,
  });
}

/// Sendable output of [DerivationEngine._computeDayBlocks]. [bundlePatch] /
/// [seriesPatch] / [scalarPatch] are merged into the isolate-1 bundle on the main
/// isolate; [wake] is persisted; [suggestionsToPersist] / [sessionHrrWrites] /
/// [notifBout] are the DB writes + notification the caller applies.
class _DayBlocksOutput {
  final Map<String, dynamic> bundlePatch;
  final Map<String, dynamic> seriesPatch;
  final Map<String, dynamic> scalarPatch;
  final Map<String, dynamic> wake;
  final List<Map<String, dynamic>> suggestionsToPersist;
  final List<(String, double)> sessionHrrWrites;
  final ({String id, int durationMin})? notifBout;
  const _DayBlocksOutput({
    required this.bundlePatch,
    required this.seriesPatch,
    required this.scalarPatch,
    required this.wake,
    required this.suggestionsToPersist,
    required this.sessionHrrWrites,
    required this.notifBout,
  });
}

/// Result of the pure workout compute ([DerivationEngine._computeWorkouts]).
class _WorkoutCompute {
  final List<Map<String, dynamic>> boutJson;
  final double? hrrBpm;
  final double? hrrTauS;
  final List<(String, double)> sessionHrrWrites;
  final List<Map<String, dynamic>> suggestionsToPersist;
  final ({String id, int durationMin})? notifBout;
  const _WorkoutCompute({
    required this.boutJson,
    required this.hrrBpm,
    required this.hrrTauS,
    required this.sessionHrrWrites,
    required this.suggestionsToPersist,
    required this.notifBout,
  });
  const _WorkoutCompute.empty()
    : boutJson = const [],
      hrrBpm = null,
      hrrTauS = null,
      sessionHrrWrites = const [],
      suggestionsToPersist = const [],
      notifBout = null;
}

double? _median(List<double> xs) {
  if (xs.isEmpty) return null;
  final vs = List<double>.from(xs)..sort();
  final mid = vs.length ~/ 2;
  return vs.length.isOdd ? vs[mid] : (vs[mid - 1] + vs[mid]) / 2;
}
