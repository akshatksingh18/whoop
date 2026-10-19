// notification_center.dart — the single emitter.
//
// Every insight and alert goes through emit(). OS-level notifications are the
// ONLY surface now — the in-app notifications feed/screen was removed (it
// duplicated the OS notification with no independent value).
//
// emit() is the PRESENT path. The standing schedules further down
// (scheduleStandingReminders, scheduleAiReminders) are the SCHEDULE path, which
// never passes through emit at all: the OS fires those with no Dart running.
// They are gated by NotificationService.schedulableIds instead.
//
// Whether an emitted event fires an OS notification is decided by
// NotificationPrefs:
//   • it must be one of the four sanctioned NotifClasses (see classOf), AND
//   • its category must be enabled, AND
//   • either we're outside quiet hours, or the event is critical and the user
//     allowed critical-overrides-quiet.
// The alarm is exempt from the last two: the user armed it for a time that is
// usually inside their own quiet window.
//
// Emit sites that are no longer one of the three (recovery-ready, step goal,
// posture, "did you work out?") still call emit() and are dropped HERE rather
// than at each site — one gate is how the rule stays true when the next emit
// site is added.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/day_label.dart';
import '../platform/signing_profile.dart';
import 'fired_keys.dart';
import 'notification_event.dart';
import 'notification_report.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';
import 'tap_router.dart';

class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  /// The persistent "already fired this dedupeKey" guard. See [FiredKeyStore].
  final FiredKeyStore _fired = const FiredKeyStore();

  /// Tail of a chained-Future lock that serialises the claim-present-release
  /// critical section in [emit]. It keeps two overlapping emits in THIS isolate
  /// from interleaving their presents — more likely now the UI-thread stress
  /// alert can race the background derive loop.
  ///
  /// It is not what enforces fire-once. This lock can only order emits WITHIN
  /// this isolate; derivation also runs in the WorkManager isolate, which it
  /// cannot see. Fire-once across both is enforced by the atomic
  /// [FiredKeyStore.claim] below — one SQLite INSERT OR IGNORE, one winner.
  Future<void> _lock = Future<void>.value();

  /// Run [action] after any in-flight critical section completes, exclusively.
  Future<void> _synchronized(Future<void> Function() action) async {
    final prev = _lock;
    final done = Completer<void>();
    _lock = done.future; // installed synchronously — orders concurrent callers
    await prev;
    try {
      await action();
    } finally {
      done.complete();
    }
  }

  /// The OS presentation sink. Returns true when the event was actually shown
  /// (permission granted, no error). Overridable in tests to assert call counts
  /// without a device; defaults to the real service.
  @visibleForTesting
  Future<bool> Function(NotificationEvent e, {bool allowPermissionPrompt})
  presentSink = NotificationService.instance.presentEvent;

  /// Present to the OS (if allowed). Never throws.
  ///
  /// [allowPermissionPrompt]: Apple's notification docs document that
  /// authorization must be requested IN CONTEXT, from an active foreground
  /// scene — never from a background execution context (a headless
  /// BGTaskScheduler run or Dart background isolate has none to present
  /// from). Callers that know they're running headless (see
  /// background_sync.dart's checkSyncStaleness) MUST pass `false`, so a
  /// not-yet-decided permission is checked, not requested, and never gets
  /// permanently mis-cached as "denied" by a background attempt.
  ///
  /// Returns TRUE only when the event actually reached the OS. Callers that
  /// keep their own "already fired today" guard (see [emitOncePerDay]) MUST key
  /// it off this, never off the mere fact that emit was called: the event is
  /// dropped outright when [NotificationPrefs.shouldFireOs] says no (quiet
  /// hours, category muted) or when the OS present fails.
  Future<bool> emit(
    NotificationEvent e, {
    bool allowPermissionPrompt = true,
  }) async {
    var presented = false;
    try {
      final prefs = await NotificationPrefs.load();
      final now = DateTime.now();
      final minuteOfDay = now.hour * 60 + now.minute;
      if (!prefs.shouldFireOs(e, minuteOfDay)) return false;
      // Enforce the dedupeKey's "fires at most once" contract (issue #136).
      // The OS id only REPLACES a prior post of the same key — it still
      // re-alerts — and derivation re-runs on every BLE sync, so an insight
      // whose condition holds all day would otherwise buzz over and over. The
      // guard resets itself per new day via the date-prefixed keys.
      //
      // CLAIM, don't check. A check-then-record pair is not atomic: the two
      // derivation isolates can both read "not fired" before either records and
      // both alert. [FiredKeyStore.claim] decides ownership in ONE atomic
      // operation, so exactly one caller — in either isolate — ever proceeds.
      //
      // A claim we don't spend is given straight back: a permission-denied
      // no-op or a throwing present must NOT consume the key, or that insight
      // stays silent for the rest of the day. Release on every non-present path
      // (hence the finally), which restores the pre-existing
      // "record only after a real present" semantics.
      await _synchronized(() async {
        if (!await _fired.claim(e.dedupeKey)) return;
        var shown = false;
        try {
          shown = await presentSink(
            e,
            allowPermissionPrompt: allowPermissionPrompt,
          );
        } finally {
          if (!shown) await _fired.release(e.dedupeKey);
        }
        presented = shown;
      });
    } catch (_) {
      /* OS present best-effort */
    }
    return presented;
  }

  /// Fire [e] at most once per [dayId], with the persisted day-guard at
  /// [prefsKey] consumed ONLY when the notification was actually presented.
  /// Returns true iff it fired.
  ///
  /// The callers of this (recovery-ready, step-goal) used to write the guard
  /// FIRST and then emit. [emit] drops the event outright when
  /// [NotificationPrefs.shouldFireOs] is false, so a band that syncs at 06:40 —
  /// inside the DEFAULT 22:00–07:00 quiet window — computed the new day's
  /// recovery, burned the guard, got suppressed, and then had every retry that
  /// day blocked by the guard it never earned: "Your recovery is ready" simply
  /// never fired. Claiming the guard only on a real present makes the retry
  /// (the next derive pass, after 07:00) work.
  ///
  /// That fix left the other half open: [dayId] is the day the DATA is from,
  /// and a suppressed event deliberately leaves the guard unspent, so the
  /// caller re-reads the SAME last row on every later foreground open. Deny
  /// notifications, walk 12k steps, leave the band in a drawer for a week, then
  /// turn notifications back on: "step goal reached" fired about a day the user
  /// wore nothing. Yesterday's news is not news — a past day never fires, and
  /// that gate belongs here, not in each caller.
  Future<bool> emitOncePerDay({
    required String prefsKey,
    required String dayId,
    required NotificationEvent e,
    bool allowPermissionPrompt = true,
  }) async {
    if (dayId.compareTo(todayLabel()) < 0) return false;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null; // no store — [emit]'s own FiredKeyStore still dedupes
    }
    if (prefs != null && prefs.getString(prefsKey) == dayId) return false;
    final shown = await emit(e, allowPermissionPrompt: allowPermissionPrompt);
    if (shown && prefs != null) {
      try {
        await prefs.setString(prefsKey, dayId);
      } catch (_) {
        /* guard is an optimisation; FiredKeyStore is the truth */
      }
    }
    return shown;
  }

  static const int recapWeekday = DateTime.sunday;
  static const int recapHour = 18; // Sunday 18:00
  static const int recapMinute = 0;

  /// Bring the OS scheduler in line with the user's prefs: the weekly lookback,
  /// armed only for a week that actually contained something ([weeklyFinding]
  /// is the whole condition — null means it isn't armed).
  ///
  /// The cancel is not conditional and must stay that way: it is what clears
  /// whatever an earlier pass — or the user's own switch, a moment ago — left
  /// standing. It runs BEFORE the permission check, deliberately — see the
  /// note in [_armWeeklyLookback].
  Future<void> scheduleStandingReminders(
    NotificationPrefs prefs, {
    String? weeklyFinding,
  }) async {
    final svc = NotificationService.instance;
    await svc.cancel(NotificationService.idWeeklyRecap);
    if (!prefs.remindersEnabled || weeklyFinding == null) return;
    // Re-resolve the zone first: this runs on every foreground resume, and the
    // instant is wall-clock. A phone that flew somewhere would otherwise keep
    // arming Sunday 18:00 in the zone the app first launched in.
    await svc.ensureTimezone();
    await _armWeeklyLookback(svc, weeklyFinding);
  }

  /// Arm the 48 h / 24 h signing-expiry warnings for [expiry] (the installed
  /// profile's), replacing whatever an earlier pass armed. A null expiry — not
  /// the personal sideload, or the profile could not be read — cancels both
  /// rather than leaving warnings for an expiry nobody can confirm.
  ///
  /// ponytail: fires at the exact moment even inside quiet hours; the profile
  /// is signed at install time, which is when someone is awake, so the 48 h and
  /// 24 h marks land at a waking hour too. Clamp into waking hours if a
  /// refresh ever lands at night and the alert becomes the complaint.
  Future<void> scheduleSigningExpiryAlerts(
    DateTime? expiry, {
    DateTime? now,
  }) async {
    final svc = NotificationService.instance;
    await svc.cancel(NotificationService.idSigningExpiry48);
    await svc.cancel(NotificationService.idSigningExpiry24);
    final plan = signingAlertPlan(expiry, now ?? DateTime.now());
    if (plan.isEmpty) return;
    await svc.ensureTimezone();
    for (final a in plan) {
      await svc.scheduleOnce(
        id: a.hoursBefore == 48
            ? NotificationService.idSigningExpiry48
            : NotificationService.idSigningExpiry24,
        category: NotifCategory.device,
        title: a.hoursBefore == 48
            ? 'WHOOP signing ends in 2 days'
            : 'WHOOP signing ends tomorrow',
        body:
            'Refresh it with Sideloadly on your PC. Once it lapses the app '
            'will not open. Opening WHOOP re-checks — if it was already '
            'refreshed, this warning moves.',
        at: a.at,
        route: kRouteStatus,
      );
    }
  }

  // ── the weekly lookback finding ─────────────────────────────────────────

  /// What Sunday's lookback says, or null when the week was quiet enough that
  /// NOTHING should interrupt the user. PURE over the crossday rollup's
  /// `recent[]` rows ({date, rhr, unsettled, illness, anomaly, temp}).
  ///
  /// The bar is deliberately high: most weeks must produce null. A weekly
  /// notification that fires every Sunday is the recap problem all over again
  /// — the reason the slot sat unwired for so long was that nothing honest
  /// could fill it. Priority: medical flags first (they are the sanctioned
  /// detections), then a plainly-stated resting-HR drift, then silence.
  static String? weeklyLookbackFinding(List<Map<String, dynamic>> recentDays) {
    final days = recentDays
        .where((d) => d['unsettled'] != true)
        .toList(growable: false);
    if (days.isEmpty) return null;

    // Medical flags, counted per kind. These reuse the same detectors the
    // daily health exception fires on — the weekly note only SUMMARIZES them.
    final illness = days.where((d) => d['illness'] == true).length;
    final anomaly = days.where((d) => d['anomaly'] == true).length;
    final temp = days.where((d) => d['temp'] == true).length;
    final parts = <String>[];
    if (illness > 0) parts.add('possible illness onset ×$illness');
    if (anomaly > 0) parts.add('unusual physiology ×$anomaly');
    if (temp > 0) parts.add('elevated skin temperature ×$temp');
    if (parts.isNotEmpty) {
      return 'This week flagged: ${parts.join(', ')}. Details live on Health.';
    }

    // Resting-HR drift across the week: mean of the last three nights vs the
    // first three. Plain arithmetic on stored nightly values, stated as such
    // — no trend test dressed up as science. Needs ≥5 settled nights with an
    // RHR on both ends, which is also what keeps this silent most weeks.
    final rhrs = [
      for (final d in days)
        if (d['rhr'] is num) (d['rhr'] as num).toDouble(),
    ];
    if (rhrs.length >= 5) {
      double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      final early = mean(rhrs.sublist(0, 3));
      final late = mean(rhrs.sublist(rhrs.length - 3));
      final delta = late - early;
      if (delta >= 3) {
        return 'Resting heart rate ran about ${delta.round()} bpm higher '
            'late in the week than early.';
      }
      if (delta <= -3) {
        return 'Resting heart rate ran about ${(-delta).round()} bpm lower '
            'late in the week than early.';
      }
    }
    return null;
  }

  Future<void> _armWeeklyLookback(
    NotificationService svc,
    String finding,
  ) async {
    final day = todayLabel();
    final report = await NotificationReport.save(
      'Your week in review',
      finding,
      day,
    );
    await svc.scheduleOnce(
      id: NotificationService.idWeeklyRecap,
      category: NotifCategory.reminders,
      title: 'Your week in review',
      body: finding,
      at: svc.nextWeeklyInstant(recapWeekday, recapHour, recapMinute),
      // A week of sleep, strain and recovery lives on Health.
      route: datedRoute(kRouteRecap, day, id: report),
    );
  }
}
