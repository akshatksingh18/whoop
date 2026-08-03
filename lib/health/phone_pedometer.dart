import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../data/db.dart';
import '../data/day_label.dart';

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
  PhonePedometer({Health? health}) : _health = health ?? Health();

  final Health _health;

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
  Future<int?> syncDay(DateTime dayStartLocal) async {
    final dayId = dayLabelOf(dayStartLocal);
    try {
      await _health.configure();
      final windows = <({int startTs, int endTs, int steps})>[];
      var total = 0;
      var anyRead = false;
      final now = DateTime.now();

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
        final from = DateTime(dayStartLocal.year, dayStartLocal.month,
            dayStartLocal.day, h);
        if (!from.isBefore(nextMidnight)) break; // spring-forward short day
        if (from.isAfter(now)) break; // future hours of today
        var to = DateTime(dayStartLocal.year, dayStartLocal.month,
            dayStartLocal.day, h + 1);
        if (to.isAfter(nextMidnight)) to = nextMidnight;
        final capped = to.isAfter(now) ? now : to;
        if (!capped.isAfter(from)) break;

        final n = await _health.getTotalStepsInInterval(from, capped);
        if (n == null) continue;
        anyRead = true;
        if (n <= 0) continue;
        windows.add((
          startTs: from.millisecondsSinceEpoch ~/ 1000,
          endTs: capped.millisecondsSinceEpoch ~/ 1000,
          steps: n,
        ));
        total += n;
      }

      // A day where every hour returned null is a FAILED read, not a zero-step
      // day. Persisting nothing keeps whatever we already had rather than
      // wiping a good previous sync.
      if (!anyRead) return null;

      await LocalDb.replacePhoneCoverageForDay(dayId, windows);
      return total;
    } catch (e) {
      debugPrint('[phone_pedometer] syncDay $dayId: $e');
      return null;
    }
  }

  /// Sync the last [days] days (including today). Returns days successfully read.
  Future<int> syncRecent({int days = 7}) async {
    if (!await hasPermission()) return 0;
    final now = DateTime.now();
    var ok = 0;
    for (var d = 0; d < days; d++) {
      // Calendar subtraction, NOT `Duration(days: d)` — the latter lands on
      // 23:00 or 01:00 across a DST transition rather than local midnight,
      // which would mislabel the day and start its hour walk at the wrong
      // offset. DateTime normalises an out-of-range day field for us.
      final day = DateTime(now.year, now.month, now.day - d);
      if (await syncDay(day) != null) ok++;
    }
    return ok;
  }
}
