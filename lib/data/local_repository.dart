// Contract for local stored-data readers and durable user commands.
// LocalRepositoryImpl implements every method; missing production endpoints
// fail at compile time. Partial authored test readers live in test/support.

import '../compute/manual_session.dart' show SessionSpan;
import '../gps/route_models.dart';
import 'journal_fields.dart';

/// The single source of truth for "no step goal configured yet" (8k/day is
/// the commonly-cited optimal benefit/cost ratio for step count). Both the
/// data layer (local_repository_impl.dart's `getProfile()`/`_stepGoal()`,
/// which is where `TodayData.stepGoal` actually gets its default BEFORE any
/// UI-level fallback ever sees a null) and the UI (the steps detail screen's
/// `_StepGoalGauge`, in ui2/screens/metric_detail.dart, seeded from this same
/// constant) must agree — they used to independently default to two different values
/// (10000 here vs. 8000 in the UI), so the UI fallback never actually
/// triggered for real profile data.
const int kDefaultStepGoal = 8000;

/// A local read or command failure. Screens render its recoverable error state.
class RepositoryException implements Exception {
  final int status;
  final String body;
  RepositoryException(this.status, this.body);
  @override
  String toString() => 'Repository error $status: $body';
}

/// Shared local contract for insight screens and user commands.
/// Readers return defensive maps/lists with explicit absence and provenance.
abstract class LocalRepository {
  // ── profile ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getProfile();
  Future<Map<String, dynamic>> setStepGoal(int goal);

  // ── today / summaries ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getToday();

  /// Sleep ONSET/OFFSET for the most recent [days] days, newest first.
  ///
  /// One projected query over `day_result.window_json` — no bundle decode and
  /// no per-day round trip, which is what an actogram (and the circadian
  /// family) needs. The alternative is N separate `getDaySleepV2` calls, each
  /// decoding a full day bundle.
  ///
  /// Rows: `{date: 'YYYY-MM-DD', onset_ts: int?, wake_ts: int?, confidence:
  /// double?, tier: String?}` — epoch SECONDS. A night with no detected sleep
  /// still appears, with null times; the caller decides what an absent night
  /// looks like rather than being handed a silently shorter list.
  Future<List<Map<String, dynamic>>> sleepWindows({
    int days = 60,
    String? before,
  });

  /// Saved sessions in the window, merged with unconfirmed auto-detected bouts.
  ///
  /// Pass `includeDetected: false` when only saved sessions are wanted: the
  /// detected half has to read every recent day bundle to find them, and those
  /// rows carry the full hr_curve/hypnogram/HRV payload.
  Future<List<Map<String, dynamic>>> getSessions({
    int? from,
    int? to,
    bool includeDetected = true,
  });

  /// Cross-day analytics rollup (illness/anomaly/load/SRI/jetlag/chronotype/
  /// sleep-debt/percentile/glass-box/BRV) — the seam the cross-day screens and
  /// notifications read. Empty map when no rollup has been computed yet.
  Future<Map<String, dynamic>> getInsights();

  // ── day drill-down detail ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDaySleepV2(String date);
  Future<Map<String, dynamic>> getDayStrain(String date);

  /// TS-03/04/05 — the observed HR ceiling, the zone edges with the anchors
  /// they were built from, and (only when both anchors were measured) the
  /// 28-day session intensity distribution.
  Future<Map<String, dynamic>> getZones();
  Future<Map<String, dynamic>> getDaySleep(String date);
  Future<Map<String, dynamic>> getDayTimeline(String date);

  /// Durable per-minute HR means, with thin/empty minutes omitted. No derive
  /// and no RAM live samples; absolute bounds can cross a local midnight.
  Future<List<Map<String, num>>> getRecordedHr(int fromSec, int toSec);

  /// HR, HRV, respiration and skin temperature over one night's absolute
  /// onset-to-wake window, read across every local day it touches (B86-03).
  /// Empty where unsupported; callers keep their day timeline then.
  Future<Map<String, dynamic>> getNightSignals(int onsetTs, int wakeTs);
  Future<Map<String, dynamic>> getDayStress(String date);
  Future<Map<String, dynamic>> getDayHeart(String date);
  Future<Map<String, dynamic>> getDayLungs(String date);
  Future<Map<String, dynamic>> getDayWear(String date);

  /// [date]'s naps, AFTER the user's own edits have been replayed over the
  /// detector's proposal — the same merged list `nap_min` is summed from, so
  /// the screen and the sleep-need credit cannot disagree about which naps
  /// happened. `{naps: [{start, end, duration_min, source?}], nap_min, note}`,
  /// and an EMPTY map when the day could not be judged at all (which is not
  /// the same as a day with no naps, and reads differently).
  Future<Map<String, dynamic>> getDayNaps(String date);
  Future<Map<String, dynamic>> getDayHrv(String date);

  /// The individual beat intervals behind [date]'s night — the substrate the
  /// Poincaré plot on Beats is drawn from, artifact-corrected exactly the way
  /// the pipeline corrected them.
  ///
  /// `nn` is the cleaned NN series in ms, in beat order; `rawBeats` is how many
  /// intervals were read before correction, so a screen can state what it threw
  /// away instead of implying the cloud is every beat of the night.
  ///
  /// EMPTY IS THE NORMAL STEADY STATE, not an error. `decoded_rr` is pruned at
  /// `rawRetentionDays` behind the data edge, so the beats exist for the last
  /// few nights and are gone forever after that — while every number computed
  /// FROM them lives in the day bundle for good. A caller must render that as
  /// "the beats are no longer on this phone", never as "no data".
  Future<({List<double> nn, int rawBeats, double cleanFraction})> getNightBeats(
    String date,
  );

  /// [date]'s steps as the RESOLVED spans behind them — when each stretch was
  /// counted, by which sensor, and inside which session if any.
  ///
  /// `{total, strap, phone, day_total, day_source, note, spans: [{start_ts,
  /// end_ts, steps, source: 'band'|'phone', activity}]}`, epoch SECONDS.
  ///
  /// The spans are post-ladder (see `resolveDaySteps`), so they sum to `total`
  /// and never show the same walk twice. `day_total`/`day_source` are the
  /// number the day actually published, which is NOT always this sum: with no
  /// span source at all a gen5 day falls back to the strap's on-chip counter,
  /// a whole-day figure with no times behind it and therefore no spans.
  /// Fresh measured movement for dependent calculations; no derived-day fallback.
  Future<num?> getMeasuredDaySteps(String date);

  Future<Map<String, dynamic>> getDaySteps(String date);

  /// Every day ('YYYY-MM-DD') the lookback screen can actually RENDER — the days
  /// with a genuine derived bundle (`getDayTimeline` returns real data for), not
  /// raw-only or skip-marker days that would render empty — newest first. Bounds
  /// the lookback screen's day navigation (the reachable prev/next days + the
  /// date-picker's selectable days). Empty when nothing has been derived yet.
  Future<List<String>> availableDays();

  // ── trends + records + charts ────────────────────────────────────────────────
  Future<Map<String, dynamic>> getRecords();
  Future<Map<String, dynamic>> getChart(String metric, {int? from, int? to});

  // ── workouts (manual / live / auto) ──────────────────────────────────────────
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'});
  Future<Map<String, dynamic>> getWorkout(String id);
  Future<void> deleteWorkout(String id);

  /// Mark a session private, or un-mark it. `getWorkout`/`getWorkouts` return
  /// the flag as `private` (bool).
  Future<void> setWorkoutPrivate(String id, bool private);

  /// Re-score recent finished sessions against the 1 Hz substrate now in the
  /// DB, correcting a live session whose in-RAM tallies missed the part of the
  /// workout the app slept through (issue #206). Returns the number of rows
  /// whose strain changed. Best-effort — never throws.
  ///
  /// The default MUST match the implementation's: Dart resolves an omitted
  /// optional from the STATIC receiver type, and every caller holds this
  /// interface — so a different default here is the one that actually runs.
  /// Three days is the raw-retention horizon; nothing older has substrate left
  /// to re-score from.
  Future<int> rescoreRecentSessions({int sinceDays = 3});

  /// Build 90 one-time repair of older workouts' stored calories: active
  /// where the shown method's inputs are known, otherwise kept and marked
  /// legacy. Returns how many rows were recalculated. Best-effort.
  Future<int> repairSessionCalorieBasis();
  Future<Map<String, dynamic>> startWorkout(String type, {String? title});
  Future<Map<String, dynamic>> endWorkout(String workoutId);

  /// Log a COMPLETED workout the athlete times themselves — one the band never
  /// detected, or detected too narrowly. Scored from the 1 Hz substrate over
  /// [startTs, endTs] (epoch SECONDS); a window with no substrate is still
  /// saved, just unscored. Returns `{workout_id, unscored, hr_samples}`.
  Future<Map<String, dynamic>> logManualWorkout({
    required int startTs,
    required int endTs,
    required String type,
  });

  /// Retime an existing session and re-score it over the new window. Used to
  /// widen an auto-detected fragment to the real session. Returns
  /// `{workout_id, unscored, hr_samples}`. Throws [StateError] when the id is
  /// unknown or the session is still live, and [ManualWindowException] when
  /// the proposed window is rejected.
  Future<Map<String, dynamic>> setWorkoutWindow(
    String id, {
    required int startTs,
    required int endTs,
  });

  /// Saved session spans (excluding stranded live rows), for the manual-entry
  /// form's overlap check.
  Future<List<SessionSpan>> savedSessionSpans();
  // GPS route for a run/ride/walk (on-device only). Null when none recorded.
  Future<WorkoutRoute?> getWorkoutRoute(String id);

  // ── journal + correlation engine ──────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getJournal({String range = '30d'});

  /// A selected day, including older nights outside the recent list window.
  Future<Map<String, dynamic>?> getJournalDay(String date);

  /// Atomically add tags, retaining the day's current note and other answers.
  Future<void> mergeJournalTags(String date, List<String> tags);

  /// MIND-12 — does one day of the week actually cost you, on ONE outcome.
  ///
  /// Deliberately one outcome and not four: the omnibus + permutation gate pays
  /// for having looked at seven weekdays, not for having also looked at four
  /// metrics. Empty map when there is nothing to say.
  Future<Map<String, dynamic>> getWeekdayEffect({String key = 'readiness'});

  /// One day's numeric journal fields, keyed by field name.
  Future<Map<String, JournalMetricValue>> getJournalMetrics(String date);

  /// One Journal edit as an atomic patch with conflict detection; see
  /// `LocalDb.saveJournalEdit`. Returns the fields someone else changed
  /// (nothing written then), or an empty list once saved.
  Future<List<String>> saveJournalEdit(
    String date, {
    required Map<String, JournalMetricValue?> changes,
    required Map<String, JournalMetricValue> base,
    List<String>? tags,
    List<String>? baseTags,
    String? note,
    String? baseNote,
  });

  /// Built-in fields followed by the user's own, in editor order.
  Future<List<JournalFieldSpec>> getJournalFields();

  Future<void> postCustomJournalField(JournalFieldSpec spec);

  Future<void> deleteCustomJournalField(String key);

  // ── menstrual cycle ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getCycle();

  // ── guided-breathing cardiac coherence ────────────────────────────────────────
  /// Decode live RR frames collected during a guided-breathing session and
  /// compute McCraty & Zayas 2014 cardiac coherence on-device. [pacedHz] is
  /// the guided pacing frequency (e.g. 5.5 breaths/min == 0.0917 Hz).
  Future<Map<String, dynamic>> breathingCoherence(
    List<String> records, {
    double? pacedHz,
  });
}
