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
import '../ai/reminder_plan.dart';
import '../data/day_label.dart';
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
      } catch (_) {/* guard is an optimisation; FiredKeyStore is the truth */}
    }
    return shown;
  }

  static const int recapWeekday = DateTime.sunday;
  static const int recapHour = 18; // Sunday 18:00
  static const int recapMinute = 0;

  /// Bring the OS scheduler in line with the user's prefs.
  ///
  /// This used to arm a wind-down nudge and an UNCONDITIONAL weekly recap on
  /// every foreground resume. What is armed now is only what the user asked for
  /// by name: the weekly lookback for a week that actually contained something
  /// ([weeklyFinding] is the whole condition — null means it isn't armed), and
  /// the hydration slots while the water reminder is on.
  ///
  /// The cancels are not conditional and must stay that way: they are what
  /// clears whatever an older build — or the user's own switch, a moment ago —
  /// left standing. They also run BEFORE the permission check, deliberately —
  /// see the note in [_armWeeklyLookback] for why the check moved down there.
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
    // idStillness is NOT a standing schedule and must not be cancelled with
    // them. It is a one-shot armed by live movement
    // (`AppState._rescheduleStillnessNudge`), nothing in this method re-arms
    // it, and this method runs on EVERY foreground resume — so the fix for
    // issue #123 was cancelling itself: open the app and the nudge was binned.
    // The re-arm needs a connected band streaming foreground IMU AND is
    // throttled to once per ten minutes, so it is not a gap that closes on its
    // own; with the band off the wrist it never closes at all.
    //
    // The one cancel that IS correct here is the user's own switch: this is
    // where a movement nudge that was just turned off actually goes away.
    if (!prefs.movementEnabled) {
      await svc.cancel(NotificationService.idStillness);
    }
    for (var i = 0; i < NotificationService.maxWaterSlots; i++) {
      await svc.cancel(NotificationService.idWaterBase + i);
    }
    final water = waterSlotMinutes(prefs);
    final wantWeekly = prefs.remindersEnabled && weeklyFinding != null;
    if (water.isEmpty && !wantWeekly) return;
    // Re-resolve the zone first: this runs on every foreground resume, and the
    // instants below are wall-clock. A phone that flew somewhere would otherwise
    // keep arming Sunday 18:00 in the zone the app first launched in.
    await svc.ensureTimezone();
    await _armWaterSlots(svc, water);
    if (wantWeekly) await _armWeeklyLookback(svc, weeklyFinding);
  }

  /// One daily-repeating notification per hydration slot.
  ///
  /// The strap buzz (WaterBuzzer) fires off the SAME [slots] list, so the two
  /// land at the same wall-clock minute — but the buzz needs a live BLE link
  /// and a live isolate, and a reminder that only arrives when the app happens
  /// to be running is not a reminder. Both fire. There is deliberately no
  /// "only notify if the strap didn't buzz" preference: nobody has felt the
  /// double yet.
  ///
  /// Copy rule: this may nudge you to LOG a drink and nothing more. The app
  /// measures no hydration, scores none, and this text may never imply either.
  Future<void> _armWaterSlots(NotificationService svc, List<int> slots) async {
    for (var i = 0; i < slots.length; i++) {
      await svc.scheduleDaily(
        id: NotificationService.idWaterBase + i,
        category: NotifCategory.reminders,
        title: 'Water',
        body: 'Tap to log a glass.',
        hour: slots[i] ~/ 60,
        minute: slots[i] % 60,
        route: kRouteWater,
      );
    }
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

  // Default waking window when quiet hours are off (so we never buzz at 3am).
  static const int _waterDayStartMin = 8 * 60; // 08:00
  static const int _waterDayEndMin = 22 * 60; // 22:00

  /// The wall-clock fire times (minutes-from-midnight, ascending) for the water
  /// reminder — one per slot across the waking window, spaced by the (clamped)
  /// interval, capped at [NotificationService.maxWaterSlots]. Empty when the
  /// reminder is off. PURE, and the ONE source both consumers read: the
  /// strap-buzz timer in AppState and [_armWaterSlots] above. That is the whole
  /// reason the buzz and the notification cannot drift apart.
  ///
  /// Gated on `waterEnabled` alone, not on `remindersEnabled` — that switch is
  /// the weekly lookback's off switch, and hanging the buzz off it is how this
  /// shipped once already with no reachable way to turn it on.
  static List<int> waterSlotMinutes(NotificationPrefs prefs) {
    if (!prefs.waterEnabled) return const [];

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

  /// Re-assert the three AI slots (morning briefing, nightly sweep, pre-sleep
  /// journal prompt).
  ///
  /// Only the nightly sweep is armed. It earns the interruption the same way
  /// the weekly lookback does — [sweepHeadline] is a finding that already
  /// exists, computed on-device before this is called, and it IS the
  /// notification's body. The morning briefing and the journal prompt are
  /// still nudges with no finding behind them; [aiReminderPlan] still describes
  /// them (it is the plan, not the policy) and
  /// [NotificationService.maySchedule] still refuses them, quietly, right here.
  ///
  /// The cancels stay unconditional: they are what clears yesterday's slot when
  /// today has nothing to say, and what clears whatever an older build left.
  Future<void> scheduleAiReminders(
    NotificationPrefs prefs,
    AiPrefs ai, {
    required bool aiConfigured,
    double? bedtimeMinOfDay,
    required bool journalDoneToday,
    String? sweepHeadline,
  }) async {
    final svc = NotificationService.instance;
    await svc.cancel(NotificationService.idMorningBrief);
    await svc.cancel(NotificationService.idEveningBrief);
    await svc.cancel(NotificationService.idJournalLog);
    final plan = aiReminderPlan(
      ai,
      remindersEnabled: prefs.remindersEnabled,
      aiConfigured: aiConfigured,
      bedtimeMinOfDay: bedtimeMinOfDay,
      journalDoneToday: journalDoneToday,
      sweepHeadline: sweepHeadline,
    ).where((s) => NotificationService.maySchedule(s.id)).toList();
    if (plan.isEmpty) return;
    await svc.ensureTimezone();
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    for (final s in plan) {
      // ONE-SHOT, and only when the slot is still ahead TODAY.
      //
      // Both halves matter and both are the same bug the weekly lookback
      // already carries a comment about. A daily REPEAT would re-announce
      // tonight's finding every night for the life of the install, because the
      // body is a fact about one specific day. And a one-shot that rolled over
      // to tomorrow would announce today's finding about a day it did not
      // happen on. Nothing is armed instead — this re-runs on the next
      // foreground pass, which is where the finding is recomputed anyway.
      if (s.hour * 60 + s.minute <= nowMin) continue;
      await svc.scheduleOnce(
        id: s.id,
        category: NotifCategory.reminders,
        title: s.title,
        body: s.body,
        at: svc.nextDailyInstant(s.hour, s.minute),
        route: s.route,
      );
    }
  }
}
