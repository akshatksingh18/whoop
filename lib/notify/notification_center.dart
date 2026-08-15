// notification_center.dart — the single emitter.
//
// Every insight, alert and nudge goes through emit(). OS-level notifications
// are the ONLY surface now — the in-app notifications feed/screen was
// removed (it duplicated the OS notification with no independent value).
// Whether an event fires an OS notification is decided by NotificationPrefs:
//   • it must be one of the three sanctioned NotifClasses (see classOf), AND
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

import '../ai/ai_prefs.dart';
import 'fired_keys.dart';
import 'notification_event.dart';
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
    } catch (_) {/* OS present best-effort */}
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
  Future<bool> emitOncePerDay({
    required String prefsKey,
    required String dayId,
    required NotificationEvent e,
    bool allowPermissionPrompt = true,
  }) async {
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
      } catch (_) {/* guard is an optimisation; FiredKeyStore is the truth */}
    }
    return shown;
  }

  static const int recapWeekday = DateTime.sunday;
  static const int recapHour = 18; // Sunday 18:00
  static const int recapMinute = 0;

  /// Bring the OS scheduler in line with the three-class rule.
  ///
  /// This used to arm a wind-down nudge, an UNCONDITIONAL weekly recap and up
  /// to 24 hydration slots on every foreground resume. Under the three-class
  /// rule only [NotifClass.lookback] may be scheduled, and only for a week that
  /// actually contained something — so [weeklyFinding] is the whole condition:
  /// null (which is every caller today) means nothing is armed at all.
  ///
  /// The cancels are not conditional and must stay that way: they are what
  /// clears whatever an older build left standing on a phone that upgrades.
  /// They also run BEFORE the permission check, deliberately — see the note in
  /// [_armWeeklyLookback] for why the check moved down there.
  ///
  /// [bedtimeMinOfDay] is no longer read: it timed the wind-down nudge. Kept so
  /// the existing caller compiles unchanged; drop both together.
  Future<void> scheduleStandingReminders(
    NotificationPrefs prefs, {
    double? bedtimeMinOfDay,
    String? weeklyFinding,
  }) async {
    final svc = NotificationService.instance;
    await svc.cancel(NotificationService.idWindDown);
    await svc.cancel(NotificationService.idWeeklyRecap);
    await svc.cancel(NotificationService.idStillness);
    for (var i = 0; i < NotificationService.maxWaterSlots; i++) {
      await svc.cancel(NotificationService.idWaterBase + i);
    }
    if (!prefs.remindersEnabled || weeklyFinding == null) return;
    await _armWeeklyLookback(svc, weeklyFinding);
  }

  /// Arm the lookback as a ONE-SHOT at the next Sunday 18:00.
  ///
  /// One-shot, not `matchDateTimeComponents: dayOfWeekAndTime`: a repeat would
  /// go on re-announcing THIS week's finding every Sunday for the life of the
  /// install, which is how the recap ended up firing unconditionally in the
  /// first place. Re-armed by the next call that has a finding.
  ///
  /// The permission check lives inside [NotificationService.scheduleOnce] and
  /// is non-prompting, so a transient "not granted" read can no longer wipe the
  /// standing schedule and leave nothing behind — the cancels above are the
  /// intended state when there is nothing to say.
  Future<void> _armWeeklyLookback(
      NotificationService svc, String finding) async {
    await svc.scheduleOnce(
      id: NotificationService.idWeeklyRecap,
      category: NotifCategory.reminders,
      title: 'Your week in review',
      body: finding,
      at: svc.nextWeeklyInstant(recapWeekday, recapHour, recapMinute),
      // A week of sleep, strain and recovery lives on Health.
      route: kRouteRecap,
    );
  }

  // Default waking window when quiet hours are off (so we never ping at 3am).
  static const int _waterDayStartMin = 8 * 60; // 08:00
  static const int _waterDayEndMin = 22 * 60; // 22:00

  /// The wall-clock fire times (minutes-from-midnight, ascending) for the
  /// hydration reminder — one per slot across the waking window, spaced by the
  /// (clamped) interval, capped at [NotificationService.maxWaterSlots]. Returns
  /// empty when hydration is off — which is now always: `waterEnabled` defaults
  /// false and the three-class rule gives it no switch to turn it on with. PURE;
  /// the only remaining consumer is the strap-buzz timer in AppState, which this
  /// therefore keeps permanently idle.
  static List<int> waterSlotMinutes(NotificationPrefs prefs) {
    if (!prefs.remindersEnabled || !prefs.waterEnabled) return const [];

    final interval = prefs.waterIntervalMin.clamp(
        NotificationPrefs.waterIntervalMinAllowed,
        NotificationPrefs.waterIntervalMaxAllowed);

    // Waking window = outside quiet hours when enabled, else the daytime default.
    // quietEnd is wake-up; quietStart is bedtime. Fall back to 08:00–22:00 if the
    // window is degenerate (start <= end, or quiet hours disabled).
    var startMin = _waterDayStartMin, endMin = _waterDayEndMin;
    if (prefs.quietEnabled && prefs.quietStartMin > prefs.quietEndMin) {
      startMin = prefs.quietEndMin; // wake
      endMin = prefs.quietStartMin; // bed
    }
    if (endMin - startMin < interval) {
      // Window too short for even one spaced slot — fire once mid-window.
      startMin = (startMin + endMin) ~/ 2;
      endMin = startMin + 1;
    }

    final slots = <int>[];
    for (var t = startMin;
        t < endMin && slots.length < NotificationService.maxWaterSlots;
        t += interval) {
      slots.add(t);
    }
    return slots;
  }

  /// Clear the three AI slots (morning briefing, evening recap, pre-sleep
  /// journal prompt).
  ///
  /// It used to schedule them from [aiReminderPlan]. All three were nudges, and
  /// none of the three had anywhere to land after the UI rebuild — there is no
  /// briefing surface and no BYOK settings screen in `lib/ui2`, so a tapped
  /// briefing opened the home screen. The plan itself is untouched (and still
  /// tested); this just stops arming it. The cancels stay so an upgrade clears
  /// slots an older build left standing.
  ///
  /// Arguments are kept so the existing caller compiles unchanged.
  Future<void> scheduleAiReminders(
    NotificationPrefs prefs,
    AiPrefs ai, {
    required bool aiConfigured,
    double? bedtimeMinOfDay,
    required bool journalDoneToday,
  }) async {
    final svc = NotificationService.instance;
    await svc.cancel(NotificationService.idMorningBrief);
    await svc.cancel(NotificationService.idEveningBrief);
    await svc.cancel(NotificationService.idJournalLog);
  }
}
