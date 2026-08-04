import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../data/db.dart';
import '../data/day_label.dart';

/// Reads steps in `[from, to)`. Null means the READ FAILED — see [syncDay].
typedef StepIntervalReader = Future<int?> Function(DateTime from, DateTime to);

/// REAL step counts, read from the phone's own pedometer.
///
/// WHY THIS EXISTS
///
/// The band is worn on the WRIST, and a wrist is a bad place to count steps.
/// Two independent limits, both measured rather than assumed:
///
///   * The 24/7 historical stream is 1 Hz. Gait is 1.4-2.3 Hz, so every gait
///     fundamental is sub-Nyquist and 80/100/140/160 spm all alias to the same
///     0.333 Hz — cadence is not merely noisy there, it is unidentifiable. No
///     published step detector exists below 10 Hz.
///   * Even at full rate, wrist amplitude ranks ordinary arm work ABOVE walking
///     (stirring ~104 mg, chopping ~139 mg vs walking ~66 mg ENMO), which is
///     why wrist devices emit 22-27 false steps/min during dishes, reaching and
///     driving (O'Connell 2017) while detecting slow walking at sensitivity
///     0.05 (Straczkiewicz 2023).
///
/// The phone rides in a pocket or bag, observes trunk motion, and runs a
/// vendor pedometer that is continuously validated against exactly this
/// problem. It is simply a better sensor for this one quantity, and it costs us
/// nothing: iOS already writes its CMPedometer counts into HealthKit and
/// Android writes to Health Connect, both on-device.
///
/// PRIVACY / LOCAL-FIRST: this is a local read from the on-device health store.
/// Nothing leaves the phone, and nothing here is written back — see
/// [HealthExport] for why we deliberately stopped writing STEPS out.
class PhonePedometer {
  /// [stepReader] exists so the hour walk is testable. `Health` has a private
  /// constructor and is a singleton factory, so it cannot be subclassed or
  /// faked from a test library — and the walk is where the DST and partial-read
  /// bugs live, so it needs coverage that does not touch a real health store.
  PhonePedometer({Health? health, StepIntervalReader? stepReader})
      : _health = health ?? Health(),
        _stepReader = stepReader;

  final Health _health;
  final StepIntervalReader? _stepReader;

  Future<int?> _readSteps(DateTime from, DateTime to) =>
      _stepReader?.call(from, to) ??
      _health.getTotalStepsInInterval(from, to);

  static const List<HealthDataType> _types = [HealthDataType.STEPS];

  /// Ask for READ access to steps. Safe to call repeatedly.
  Future<bool> requestPermission() async {
    try {
      await _health.configure();
      final already = await _health.hasPermissions(
        _types,
        permissions: const [HealthDataAccess.READ],
      );
      if (already == true) return true;
      return await _health.requestAuthorization(
        _types,
        permissions: const [HealthDataAccess.READ],
      );
    } catch (e) {
      debugPrint('[phone_pedometer] permission: $e');
      return false;
    }
  }

  /// Best-effort permission probe. `null` is treated as MAYBE, not NO.
  ///
  /// Health Connect's `hasPermissions` frequently returns null/false even after
  /// the user has granted everything — `HealthExport` documents this exact
  /// behaviour and deliberately attempts every write rather than gating on the
  /// check. Gating a READ on it here would reintroduce that failure: on Android
  /// phone steps could silently never sync after a successful grant, and the
  /// user would see only a missing step count with nothing to act on.
  ///
  /// So this returns false ONLY on an explicit `false`. A null (unknown) result
  /// lets the read proceed and lets the platform enforce — an ungranted read
  /// simply returns no data, which `syncDay` already treats as "unknown", not
  /// as zero.
  Future<bool> hasPermission() async {
    try {
      await _health.configure();
      final r = await _health.hasPermissions(
        _types,
        permissions: const [HealthDataAccess.READ],
      );
      return r != false; // null => attempt anyway
    } catch (e) {
      debugPrint('[phone_pedometer] hasPermission: $e');
      return true; // probe failed; let the read attempt decide
    }
  }

  /// Read [day]'s steps in hourly buckets and replace that day's phone rows.
  ///
  /// Hourly rather than one daily total so the derivation keeps a usable notion
  /// of WHEN the steps happened, and so a partially-elapsed today still banks
  /// what has happened so far.
  ///
  /// Uses `getTotalStepsInInterval`, which on iOS is an HKStatisticsQuery
  /// cumulative sum — HealthKit de-duplicates overlapping samples from multiple
  /// sources (iPhone + Watch) itself, which a raw sample read would not.
  ///
  /// Returns the day's total, or null if the read failed or was not permitted
  /// (null means "unknown", NOT zero — the caller must not persist a zero).
  ///
  /// A null from ANY hour aborts the whole day. `null` from this plugin means
  /// the query FAILED, not that the hour was empty — verified in both native
  /// implementations at health 11.1.1:
  ///
  ///   * iOS `SwiftHealthPlugin.swift`: `HKStatisticsQuery` returns `nil` only
  ///     via `guard let queryResult else { result(nil) }`. An hour with no
  ///     samples has a nil `sumQuantity()` but still falls through to
  ///     `steps = 0.0` and returns `0`.
  ///   * Android `HealthPlugin.kt`: `response[StepsRecord.COUNT_TOTAL] ?: 0L`
  ///     returns `0` for an empty range; `result.success(null)` happens only in
  ///     the `catch`.
  ///
  /// So a partial read is a real failure, and it must not be persisted:
  /// [LocalDb.replacePhoneCoverageForDay] is delete-then-insert, so banking a
  /// short read would LOWER a previously complete day. And because
  /// [LocalDb.liveStepsForDay] prefers phone rows outright, the truncated total
  /// would also keep suppressing the band fallback.
  Future<int?> syncDay(DateTime dayStartLocal) async {
    final dayId = dayLabelOf(dayStartLocal);
    try {
      // Only touch the platform when we are actually going through it.
      if (_stepReader == null) await _health.configure();
      final windows = <({int startTs, int endTs, int steps})>[];
      var total = 0;
      var anyRead = false;

      // CALENDAR-AWARE hour walk. `Duration` arithmetic on a local DateTime is
      // ABSOLUTE, so `dayStartLocal.add(Duration(hours: h))` over a fixed 24
      // iterations spans 25 wall-clock hours on a fall-back day (the last
      // bucket crosses into the next local day and its steps get counted
      // twice) and 23 on a spring-forward day (one real hour never queried).
      // Constructing each boundary from calendar fields lets the runtime place
      // the instant correctly, and the next-midnight bound ends the day exactly.
      final nextMidnight = DateTime(
        dayStartLocal.year,
        dayStartLocal.month,
        dayStartLocal.day + 1,
      );
      for (var h = 0; h < 25; h++) {
        // RE-READ THE CLOCK EACH ITERATION. Each bucket is an async platform
        // query, so a whole day's walk can straddle an hour boundary. Captured
        // once up front, `now` went stale mid-loop and the current hour was
        // capped short — under-reporting today's most recent steps until some
        // later sync happened to re-read the day.
        final now = DateTime.now();
        final from = DateTime(dayStartLocal.year, dayStartLocal.month,
            dayStartLocal.day, h);
        if (!from.isBefore(nextMidnight)) break; // spring-forward short day
        if (from.isAfter(now)) break; // future hours of today
        var to = DateTime(dayStartLocal.year, dayStartLocal.month,
            dayStartLocal.day, h + 1);
        if (to.isAfter(nextMidnight)) to = nextMidnight;
        final capped = to.isAfter(now) ? now : to;
        // SKIP a zero-length bucket, never END the walk on one. On a
        // spring-forward day the missing local hour makes `DateTime(y,m,d,2)`
        // and `DateTime(y,m,d,3)` resolve to the SAME instant, so `h = 2` is
        // zero-width. Breaking here left every remaining hour of that day
        // unqueried while `anyRead` was already true from the earlier hours, so
        // the day was REPLACED with ~3 hours of windows — and since phone rows
        // win over band rows, that truncated total stuck permanently once the
        // day aged out of the `syncRecent` window.
        //
        // The "reached now" case does not need a break here: the next
        // iteration's `from` is after `now` and the guard above ends the walk.
        if (!capped.isAfter(from)) continue;

        final n = await _readSteps(from, capped);
        // Read failure (see the doc above) — abandon the day rather than
        // persist a partial one over a good previous sync.
        if (n == null) return null;
        anyRead = true;
        if (n <= 0) continue;
        windows.add((
          startTs: from.millisecondsSinceEpoch ~/ 1000,
          endTs: capped.millisecondsSinceEpoch ~/ 1000,
          steps: n,
        ));
        total += n;
      }

      // No hour was ever polled (a day entirely in the future, or a walk that
      // produced no buckets at all). Nothing was read, so nothing is known.
      if (!anyRead) return null;

      await LocalDb.replacePhoneCoverageForDay(dayId, windows);
      return total;
    } catch (e) {
      debugPrint('[phone_pedometer] syncDay $dayId: $e');
      return null;
    }
  }

  /// Days pulled on a routine (launch / post-export) sync.
  ///
  /// One platform round trip PER HOUR PER DAY, so the window is the whole cost:
  /// the original 7-day default was up to 168 sequential `getTotalStepsInInterval`
  /// calls, fired on every launch and again after every health export. Only
  /// today can still change, and yesterday only if the app did not run then, so
  /// two days covers the routine case at ~48 calls.
  static const int routineSyncDays = 2;

  /// Days pulled on an EXPLICIT sync (the user enabling the toggle, or a manual
  /// health sync) — the backfill window, worth its cost because the user asked.
  static const int fullSyncDays = 7;

  /// Sync the last [days] days (including today).
  ///
  /// Returns how many days were read successfully and the steps they held. The
  /// caller surfaces this: "permission granted but no data ever arrives" is
  /// otherwise a silent dead end on iOS, where `requestAuthorization` reports
  /// success even when the user denied READ.
  Future<({int daysRead, int totalSteps})> syncRecent({
    int days = routineSyncDays,
  }) async {
    if (_stepReader == null && !await hasPermission()) {
      return (daysRead: 0, totalSteps: 0);
    }
    final now = DateTime.now();
    var ok = 0;
    var total = 0;
    for (var d = 0; d < days; d++) {
      // Calendar subtraction, NOT `Duration(days: d)` — the latter lands on
      // 23:00 or 01:00 across a DST transition rather than local midnight,
      // which would mislabel the day and start its hour walk at the wrong
      // offset. DateTime normalises an out-of-range day field for us.
      final day = DateTime(now.year, now.month, now.day - d);
      final n = await syncDay(day);
      if (n != null) {
        ok++;
        total += n;
      }
    }
    return (daysRead: ok, totalSteps: total);
  }
}
