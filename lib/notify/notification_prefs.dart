// notification_prefs.dart — user control over what reaches the OS shade.
//
// Persisted in shared_preferences. The in-app feed is ALWAYS written (it's the
// user's own history); these prefs only gate whether an event also fires an OS
// notification, and whether it may break through the quiet-hours window.
//
// Decision (user-chosen): health-critical alerts override quiet hours by default;
// recovery + reminders stay silent during the quiet window.

import 'package:shared_preferences/shared_preferences.dart';
import '../state/prefs.dart';

import 'notification_event.dart';
import 'tap_router.dart';

class NotificationPrefs {
  /// The day's aggregated health exception (illness, unusual physiology,
  /// elevated temperature, an irregular-rhythm screen, low readiness, a shifted
  /// resting-HR trend — one notification, not six).
  final bool healthEnabled;

  /// Retained for storage compatibility. Nothing on the `recovery` channel is
  /// one of the three sanctioned classes any more — see [classOf].
  final bool recoveryEnabled;

  /// The weekly lookback.
  final bool remindersEnabled;

  /// The band's own failures: flat battery, on the charger, gone quiet. This
  /// used to be hard-coded enabled with no switch anywhere.
  final bool deviceEnabled;

  /// Quiet window as minutes-from-midnight. Wraps midnight when start > end
  /// (e.g. 22:00–07:00 → start=1320, end=420).
  final int quietStartMin;
  final int quietEndMin;
  final bool quietEnabled;

  /// When true, NotifPriority.critical events fire even inside quiet hours.
  final bool criticalOverridesQuiet;

  /// Whether the auto-detected-workout surfaces are on: the "did you work out?"
  /// notification and the review cards the detector feeds. Asked for twice
  /// (issues #102, #149) and never built — the detector has never had an off
  /// switch of any kind.
  ///
  /// WHAT IT DOES NOT DO: stop the detection itself. The bouts are computed
  /// inside the day derivation and written to `workout_suggestions` there; this
  /// switch silences every surface that shows them, which is the part the user
  /// experiences. The rows stay, unread, and turning it back on shows them
  /// again rather than losing a week of them.
  final bool autoDetectEnabled;

  /// The low-battery alert threshold, in percent. DeviceAlerts used to
  /// hard-code 15%; this is the same alert with the number in the user's
  /// hands. Read back by DeviceAlerts through its own persisted store (same
  /// key), so a headless BLE state update picks up a change without a full
  /// NotificationPrefs load. Clamped to [batteryPctAllowed] when scheduling.
  final int batteryAlertPct;

  /// B88-12 (C8): health-alert kinds the user switched off, by
  /// `FindingKind.name`. A muted kind still appears in the in-app findings
  /// log; it only never reaches the notification.
  final Set<String> mutedFindings;

  /// Allowed bounds for [batteryAlertPct]. Below 5% a band is dying, not low;
  /// above 40% the alert would fire constantly and be muted forever.
  static const int batteryPctMin = 5;
  static const int batteryPctMax = 40;

  /// The shipped default threshold — what an unset store degrades to (also
  /// DeviceAlerts' fallback, so the number is spelled exactly once).
  static const int batteryPctDefault = 15;

  const NotificationPrefs({
    this.healthEnabled = true,
    this.recoveryEnabled = true,
    this.remindersEnabled = true,
    this.deviceEnabled = true,
    this.quietEnabled = true,
    this.quietStartMin = 22 * 60, // 22:00
    this.quietEndMin = 7 * 60, // 07:00
    this.criticalOverridesQuiet = true,
    this.autoDetectEnabled = true,
    this.batteryAlertPct = batteryPctDefault,
    this.mutedFindings = const {},
  });

  static const _kHealth = 'notif_health';
  static const _kRecovery = 'notif_recovery';
  static const _kReminders = 'notif_reminders';
  static const _kDevice = 'notif_device';
  static const _kQuietEnabled = 'notif_quiet_enabled';
  static const _kQuietStart = 'notif_quiet_start';
  static const _kQuietEnd = 'notif_quiet_end';
  static const _kCriticalOverride = 'notif_critical_override';
  static const _kAutoDetect = 'notif_auto_detect';

  /// The low-battery alert threshold's persisted key. PUBLIC because
  /// DeviceAlerts reads it back through its own store seam on headless BLE
  /// state updates, without loading a full [NotificationPrefs]. Both sides of
  /// that coupling must spell it once.
  static const String batteryPctPrefKey = 'notif_battery_pct';
  static const _kBatteryPct = batteryPctPrefKey;
  static const _kMutedFindings = 'notif_muted_findings';

  static Future<NotificationPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return NotificationPrefs(
      healthEnabled: p.getBool(_kHealth) ?? true,
      recoveryEnabled: p.getBool(_kRecovery) ?? true,
      remindersEnabled: p.getBool(_kReminders) ?? true,
      deviceEnabled: p.getBool(_kDevice) ?? true,
      quietEnabled: p.getBool(_kQuietEnabled) ?? true,
      quietStartMin: p.getInt(_kQuietStart) ?? 22 * 60,
      quietEndMin: p.getInt(_kQuietEnd) ?? 7 * 60,
      criticalOverridesQuiet: p.getBool(_kCriticalOverride) ?? true,
      autoDetectEnabled: p.getBool(_kAutoDetect) ?? true,
      batteryAlertPct: ((p.getInt(_kBatteryPct) ?? batteryPctDefault).clamp(
        batteryPctMin,
        batteryPctMax,
      )).toInt(),
      mutedFindings: {...?p.getStringList(_kMutedFindings)},
    );
  }

  Future<void> save() async {
    await Prefs.saveValues({
      _kHealth: healthEnabled,
      _kRecovery: recoveryEnabled,
      _kReminders: remindersEnabled,
      _kDevice: deviceEnabled,
      _kQuietEnabled: quietEnabled,
      _kQuietStart: quietStartMin,
      _kQuietEnd: quietEndMin,
      _kCriticalOverride: criticalOverridesQuiet,
      _kAutoDetect: autoDetectEnabled,
      _kBatteryPct: batteryAlertPct.clamp(batteryPctMin, batteryPctMax).toInt(),
      _kMutedFindings: mutedFindings.toList()..sort(),
    });
  }

  NotificationPrefs copyWith({
    bool? healthEnabled,
    bool? recoveryEnabled,
    bool? remindersEnabled,
    bool? deviceEnabled,
    bool? quietEnabled,
    int? quietStartMin,
    int? quietEndMin,
    bool? criticalOverridesQuiet,
    bool? autoDetectEnabled,
    int? batteryAlertPct,
    Set<String>? mutedFindings,
  }) => NotificationPrefs(
    healthEnabled: healthEnabled ?? this.healthEnabled,
    recoveryEnabled: recoveryEnabled ?? this.recoveryEnabled,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    deviceEnabled: deviceEnabled ?? this.deviceEnabled,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    quietStartMin: quietStartMin ?? this.quietStartMin,
    quietEndMin: quietEndMin ?? this.quietEndMin,
    criticalOverridesQuiet:
        criticalOverridesQuiet ?? this.criticalOverridesQuiet,
    autoDetectEnabled: autoDetectEnabled ?? this.autoDetectEnabled,
    batteryAlertPct: batteryAlertPct ?? this.batteryAlertPct,
    mutedFindings: mutedFindings ?? this.mutedFindings,
  );

  bool categoryEnabled(NotifCategory c) => switch (c) {
    NotifCategory.health => healthEnabled,
    NotifCategory.recovery => recoveryEnabled,
    NotifCategory.reminders => remindersEnabled,
    NotifCategory.device => deviceEnabled,
  };

  /// True if [minuteOfDay] falls inside the quiet window (inclusive start,
  /// exclusive end), handling the midnight-wrap case.
  bool inQuietHours(int minuteOfDay) {
    if (!quietEnabled) return false;
    if (quietStartMin == quietEndMin) return false; // empty window
    if (quietStartMin < quietEndMin) {
      return minuteOfDay >= quietStartMin && minuteOfDay < quietEndMin;
    }
    // Wraps midnight: e.g. [22:00, 24:00) ∪ [00:00, 07:00)
    return minuteOfDay >= quietStartMin || minuteOfDay < quietEndMin;
  }

  /// The central gate: should this event be presented to the OS right now?
  ///
  /// This is also where the three-class rule is enforced — one gate rather than
  /// a check at each of the emit sites, which is how twenty-two kinds accreted
  /// in the first place.
  bool shouldFireOs(NotifEvent event, int minuteOfDay) {
    // The auto-detect off switch, applied before anything else: it is the one
    // gate the user set for THIS notification, and route is what identifies it
    // (the category it is emitted on is shared with everything else on the
    // recovery channel).
    // (On the PATH: the payload carries the bout as `?id=…`, and an equality
    // check against the bare route would miss every real one.)
    if (!autoDetectEnabled &&
        (routePath(event.route ?? '') == kRouteWorkoutSuggestion ||
            routePath(event.route ?? '') == kRouteWorkoutIdle)) {
      return false;
    }
    final klass = classOf(event);
    if (klass == null) return false; // not one of the three — never fires
    // The alarm is the one thing quiet hours must not silence: the user armed
    // it FOR a time, usually inside the quiet window, and its off switch is
    // cancelling the alarm rather than a preference buried in settings.
    if (klass == NotifClass.alarm) return true;
    // Reminder-channel prompts have their own switches, so the reminders
    // category switch (Weekly lookback) does not also silence them.
    if (event.category != NotifCategory.reminders &&
        !categoryEnabled(event.category)) {
      return false;
    }
    if (inQuietHours(minuteOfDay)) {
      return event.priority == NotifPriority.critical && criticalOverridesQuiet;
    }
    return true;
  }
}

// Alias kept short for the gate signature above.
typedef NotifEvent = NotificationEvent;
