// notification_prefs.dart — user control over what reaches the OS shade.
//
// Persisted in shared_preferences. The in-app feed is ALWAYS written (it's the
// user's own history); these prefs only gate whether an event also fires an OS
// notification, and whether it may break through the quiet-hours window.
//
// Decision (user-chosen): health-critical alerts override quiet hours by default;
// recovery + reminders stay silent during the quiet window.

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_event.dart';

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

  /// Water reminder: a recurring strap buzz across the waking window, every
  /// [waterIntervalMin] minutes. It is a nudge to LOG a drink and nothing more
  /// — the app measures no hydration and claims none. Opt-in, off by default.
  final bool waterEnabled;

  /// How often the water buzz fires, in minutes. Clamped to
  /// [waterIntervalMinAllowed]..[waterIntervalMaxAllowed] when scheduling.
  final int waterIntervalMin;

  /// Allowed bounds for the water interval (30 min .. 6 h).
  static const int waterIntervalMinAllowed = 30;
  static const int waterIntervalMaxAllowed = 360;

  const NotificationPrefs({
    this.healthEnabled = true,
    this.recoveryEnabled = true,
    this.remindersEnabled = true,
    this.deviceEnabled = true,
    this.quietEnabled = true,
    this.quietStartMin = 22 * 60, // 22:00
    this.quietEndMin = 7 * 60, // 07:00
    this.criticalOverridesQuiet = true,
    this.waterEnabled = false,
    this.waterIntervalMin = 120, // every 2 hours
  });

  static const _kHealth = 'notif_health';
  static const _kRecovery = 'notif_recovery';
  static const _kReminders = 'notif_reminders';
  static const _kDevice = 'notif_device';
  static const _kQuietEnabled = 'notif_quiet_enabled';
  static const _kQuietStart = 'notif_quiet_start';
  static const _kQuietEnd = 'notif_quiet_end';
  static const _kCriticalOverride = 'notif_critical_override';
  static const _kWater = 'notif_water';
  static const _kWaterInterval = 'notif_water_interval';

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
      waterEnabled: p.getBool(_kWater) ?? false,
      waterIntervalMin: p.getInt(_kWaterInterval) ?? 120,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHealth, healthEnabled);
    await p.setBool(_kRecovery, recoveryEnabled);
    await p.setBool(_kReminders, remindersEnabled);
    await p.setBool(_kDevice, deviceEnabled);
    await p.setBool(_kQuietEnabled, quietEnabled);
    await p.setInt(_kQuietStart, quietStartMin);
    await p.setInt(_kQuietEnd, quietEndMin);
    await p.setBool(_kCriticalOverride, criticalOverridesQuiet);
    await p.setBool(_kWater, waterEnabled);
    await p.setInt(_kWaterInterval, waterIntervalMin);
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
    bool? waterEnabled,
    int? waterIntervalMin,
  }) =>
      NotificationPrefs(
        healthEnabled: healthEnabled ?? this.healthEnabled,
        recoveryEnabled: recoveryEnabled ?? this.recoveryEnabled,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        deviceEnabled: deviceEnabled ?? this.deviceEnabled,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStartMin: quietStartMin ?? this.quietStartMin,
        quietEndMin: quietEndMin ?? this.quietEndMin,
        criticalOverridesQuiet:
            criticalOverridesQuiet ?? this.criticalOverridesQuiet,
        waterEnabled: waterEnabled ?? this.waterEnabled,
        waterIntervalMin: waterIntervalMin ?? this.waterIntervalMin,
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
    final klass = classOf(event);
    if (klass == null) return false; // not one of the three — never fires
    // The alarm is the one thing quiet hours must not silence: the user armed
    // it FOR a time, usually inside the quiet window, and its off switch is
    // cancelling the alarm rather than a preference buried in settings.
    if (klass == NotifClass.alarm) return true;
    if (!categoryEnabled(event.category)) return false;
    if (inQuietHours(minuteOfDay)) {
      return event.priority == NotifPriority.critical && criticalOverridesQuiet;
    }
    return true;
  }
}

// Alias kept short for the gate signature above.
typedef NotifEvent = NotificationEvent;
