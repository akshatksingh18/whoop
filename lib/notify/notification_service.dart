// notification_service.dart — the ONE place OS-level notifications are presented.
//
// It is source-agnostic: device alerts (battery/charging), derive-driven insights
// (illness, recovery), and scheduled nudges (wind-down, weekly recap, move) all
// flow through here. NotificationCenter decides *whether* to fire; this class is
// purely the OS presentation + scheduling layer.
//
// Design guarantees:
//   • Two gates, two rules. NotificationPrefs.shouldFireOs decides what may be
//     PRESENTED, and holds the three-class rule there. [schedulableIds] decides
//     what may be SCHEDULED — the OS fires a zonedSchedule with no Dart
//     running, so the presentation gate never sees one, and a scheduled slot is
//     allowed on a different test: the user asked for it by name, at a time or
//     interval they picked, and it has something to say when it fires.
//   • One channel per category (NotifCategory) so Android users mute each kind
//     independently. The `health` channel is max-importance (illness alerts).
//   • Notification ids are partitioned by NotificationEvent.osId; fixed device +
//     scheduled-reminder ids live in disjoint low bands (< 3000).
//   • One init, one permission prompt.
//   • Local + scheduled only — NO FCM/APNs (this app is cloud-free by design).
//     `kServerIdBase` stays reserved-but-unused for any future push layer.
//
// Tap routing: a tapped notification's payload (a deep-link route) is pushed onto
// [taps]; AppState listens and navigates.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/pushup_reminders.dart'
    show
        kPushupCategory,
        kPushupDoneAction,
        kPushupPauseAction,
        pushupNotificationBackground,
        PushupReminders;
import '../data/food_day_reminder.dart'
    show FoodDayReminder, kFoodCompleteAction, kFoodDayCategory,
        kFoodNotYetAction;
import 'notification_event.dart';
import 'tap_router.dart';
import 'notification_ids.dart';

/// The next wall-clock instant at [hour]:[minute] — optionally the next
/// [weekday] — strictly after [now], in [now]'s own timezone.
///
/// CALENDAR arithmetic, never an absolute [Duration]. `d.add(const
/// Duration(days: 1))` adds exactly 24 hours of ELAPSED time, which is NOT "the
/// same wall-clock time tomorrow" across a DST transition: a Sunday-18:00
/// weekly recap computed over a spring-forward landed at 19:00 (and 17:00 over
/// a fall-back), and the bedtime/hydration dailies drifted the same hour.
/// Rebuilding the [tz.TZDateTime] from its calendar fields pins the wall-clock
/// time and lets the tz database resolve whatever offset that day carries.
@visibleForTesting
tz.TZDateTime nextInstanceOf(
  tz.TZDateTime now,
  int hour,
  int minute, {
  int? weekday,
}) {
  final loc = now.location;
  tz.TZDateTime at(int y, int m, int d) =>
      tz.TZDateTime(loc, y, m, d, hour, minute);
  var d = at(now.year, now.month, now.day);
  if (weekday != null) {
    // Bounded: any weekday is at most 6 calendar days away.
    for (var i = 0; i < 7 && d.weekday != weekday; i++) {
      d = at(d.year, d.month, d.day + 1);
    }
  }
  if (!d.isAfter(now)) {
    d = at(d.year, d.month, d.day + (weekday != null ? 7 : 1));
  }
  return d;
}

/// The same wall-clock time on the following calendar day (DST-safe — see
/// [nextInstanceOf]).
@visibleForTesting
tz.TZDateTime nextCalendarDay(tz.TZDateTime d) =>
    tz.TZDateTime(d.location, d.year, d.month, d.day + 1, d.hour, d.minute);

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _tzdbLoaded = false;
  bool? _granted;

  /// Deep-link routes from tapped notifications. AppState listens & navigates.
  final StreamController<String> _taps = StreamController<String>.broadcast();
  Stream<String> get taps => _taps.stream;

  // ── Channels (one per category — keep them disjoint) ────────────────────────
  static const AndroidNotificationChannel _deviceChannel =
      AndroidNotificationChannel(
        'device_alerts',
        'Device alerts',
        description: 'Band battery and charging',
        importance: Importance.high,
      );
  static const AndroidNotificationChannel _healthChannel =
      AndroidNotificationChannel(
        'health',
        'Health alerts',
        description: 'Illness, unusual physiology and temperature signals',
        importance: Importance.max,
      );
  static const AndroidNotificationChannel _recoveryChannel =
      AndroidNotificationChannel(
        'recovery',
        'Recovery',
        description: 'Daily recovery readiness from your own data',
        importance: Importance.defaultImportance,
      );
  static const AndroidNotificationChannel _remindersChannel =
      AndroidNotificationChannel(
        'reminders',
        'Reminders',
        description: 'Weekly recap, Food, Body, Pushups and workout reminders',
        importance: Importance.defaultImportance,
      );

  // ── Fixed ids: device alerts + scheduled reminders (disjoint low band) ───────
  static const int idLowBattery = 1001;
  static const int idCharging = 1002;
  static const int idWeeklyRecap = 2003; // scheduled weekly

  /// The personal sideload's signing-expiry warnings, 48 h and 24 h before the
  /// installed profile lapses (`signing_profile.dart`). One-shots, re-armed on
  /// every foreground pass from the profile actually installed, so a refresh
  /// that moved the expiry replaces them.
  static const int idSigningExpiry48 = 2410;
  static const int idSigningExpiry24 = 2411;

  /// Lift Log inside the workout (build 86): the one-hour "Still working
  /// out?" for a session with a set log, re-armed on every entry, and the
  /// optional rest timer's alert. One-shots the user started by logging.
  static const int idLiftInactivity = 2420;
  static const int idRestTimer = 2421;

  /// Body's optional weekly measurement-day reminder (build 86).
  static const int idBodyReminder = 2422;
  // Build 89: "Is today's food complete?" (FoodDayReminder), daily.
  static const int idFoodDayReminder = 2423;

  /// Pushups (build 86): the ordinary reminder, its band of ten-minute nudges
  /// and the idle 9:00 AM start invitation. iOS keeps at most 64 pending
  /// requests for the whole app, so the batch is bounded at
  /// [maxPushupNudges] and topped up on every foreground pass; everything
  /// else this app schedules fits in the remainder.
  static const int idPushupRegular = 2500;
  static const int idPushupNudgeBase = 2501;
  static const int maxPushupNudges = 29;
  static const int idPushupDailyStart = 2540;

  /// Reserved for a future server/push layer (unused — app is cloud-free).
  static const int kServerIdBase = 2000;

  /// The OS scheduler's allow-list.
  ///
  /// [NotificationPrefs.shouldFireOs] gates what may be PRESENTED; a
  /// `zonedSchedule` never passes through it (the OS fires those with no Dart
  /// running), so what may be SCHEDULED is gated here instead.
  ///
  /// The rule this enforces is that a scheduled slot must be one the user
  /// ASKED FOR by name, with a time or an interval they chose, and must have
  /// something to say when it fires — [idWeeklyRecap], for example, is armed
  /// only for a week that actually contained a finding.
  static const Set<int> schedulableIds = {
    // The signing-expiry warnings: armed only on the personal sideload, only
    // from the expiry of the profile actually installed.
    idSigningExpiry48,
    idSigningExpiry24,
    idLiftInactivity,
    idRestTimer,
    idBodyReminder,
    idFoodDayReminder,
    idPushupRegular,
    idPushupDailyStart,
    idWeeklyRecap,
  };

  /// The gate itself — see [schedulableIds].
  static bool maySchedule(int id) =>
      schedulableIds.contains(id) || isPushupNudge(id);

  /// Whether [id] is one of the Pushups nudges — a band, like the others.
  static bool isPushupNudge(int id) =>
      id >= idPushupNudgeBase && id < idPushupNudgeBase + maxPushupNudges;

  AndroidNotificationChannel _channelFor(NotifCategory c) => switch (c) {
    NotifCategory.health => _healthChannel,
    NotifCategory.recovery => _recoveryChannel,
    NotifCategory.reminders => _remindersChannel,
    NotifCategory.device => _deviceChannel,
  };

  Importance _importanceFor(NotifCategory c) =>
      c == NotifCategory.health ? Importance.max : Importance.defaultImportance;
  Priority _priorityFor(NotifCategory c) =>
      c == NotifCategory.health ? Priority.max : Priority.defaultPriority;

  /// Point `tz.local` at the phone's CURRENT zone.
  ///
  /// Deliberately not behind [_inited]: this used to run once at cold start, so
  /// a 22:00 reminder armed in London stayed armed for 22:00 London after the
  /// user landed in Tokyo — every reschedule read the same frozen `tz.local`
  /// and could never correct it. And a single plugin failure at launch left
  /// `tz.local` as UTC for the life of the install. Re-resolving before each
  /// arm fixes both. Cheap: one channel call, and only on the schedule path.
  Future<void> ensureTimezone() async {
    try {
      // The database load is the expensive half and never changes; only the
      // zone the phone is standing in does.
      if (!_tzdbLoaded) {
        tzdata.initializeTimeZones();
        _tzdbLoaded = true;
      }
      final name = await FlutterTimezone.getLocalTimezone();
      if (name != tz.local.name) tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      /* tz stays as-is (UTC on a cold failure); we retry next arm */
    }
  }

  /// Set up the plugin, channels, timezone db and the tap handler. Idempotent.
  /// Does NOT prompt for permission.
  Future<void> init() async {
    if (_inited) return;
    await ensureTimezone();

    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    // Pushups reminders carry Done and Pause. Neither opens the app: both
    // run in the background handler, which records the action and moves the
    // reminders (pushup_reminders.dart).
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          kPushupCategory,
          actions: [
            DarwinNotificationAction.plain(kPushupDoneAction, 'Done'),
            DarwinNotificationAction.plain(kPushupPauseAction, 'Pause'),
          ],
        ),
        // Build 89: the evening food question. "Mark complete" opens the app
        // (foreground), where the tap handler records the mark.
        DarwinNotificationCategory(
          kFoodDayCategory,
          actions: [
            DarwinNotificationAction.plain(
              kFoodCompleteAction,
              'Mark complete',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(kFoodNotYetAction, 'Not yet'),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: pushupNotificationBackground,
    );
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(_deviceChannel);
    await androidImpl?.createNotificationChannel(_healthChannel);
    await androidImpl?.createNotificationChannel(_recoveryChannel);
    await androidImpl?.createNotificationChannel(_remindersChannel);
    _inited = true;
  }

  void _onTap(NotificationResponse r) {
    if (r.actionId == kPushupDoneAction || r.actionId == kPushupPauseAction) {
      PushupReminders.onAction(r, background: false);
      return;
    }
    if (r.actionId == kFoodNotYetAction) return;
    if (r.actionId == kFoodCompleteAction) {
      FoodDayReminder.onComplete();
    }
    final route = r.payload;
    if (route != null && route.isNotEmpty) _taps.add(route);
  }

  /// If the app was launched by tapping a notification, replay its route once.
  Future<void> consumeLaunchRoute() async {
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) {
        final route = d?.notificationResponse?.payload;
        if (route != null && route.isNotEmpty) _taps.add(route);
      }
    } catch (_) {}
  }

  /// Request notification permission once (iOS always; Android 13+). Cached.
  ///
  /// [allowPrompt] gates whether this may show the OS's interactive
  /// authorization dialog. Apple's notification docs ("Asking permission to
  /// use notifications") document that authorization should be requested in
  /// CONTEXT — the interactive prompt assumes an active foreground scene to
  /// present from — never automatically, and never from a background
  /// execution context (a headless BGTaskScheduler/BGAppRefreshTask run or a
  /// Dart background isolate has no such scene). Callers that know they're
  /// running headless (see background_sync.dart's checkSyncStaleness) must
  /// pass `allowPrompt: false`; every foreground/contextual caller keeps the
  /// default `true`. With `false` and no prior decision cached, this checks
  /// (never requests) via `checkPermissions()` and fails closed to `false`
  /// rather than attempting to prompt — matching the "in-app feed is ALWAYS
  /// written, OS presentation is best-effort" contract in NotificationCenter.
  ///
  /// A cached DENIAL is never final. `_granted` used to latch false for the
  /// whole process with nothing to reset it, so a user who denied the prompt
  /// (fired at pairing time), went to OS Settings, enabled notifications and
  /// came back got ZERO notifications and ZERO scheduled reminders until a full
  /// app restart — every presentEvent/scheduleDaily/scheduleWeekly/scheduleOnce
  /// early-returned on the stale `false`. Only a GRANT is cached now; a denial
  /// is re-read from the live OS state (non-prompting, cheap) on the next call.
  /// [invalidatePermissionCache] additionally drops a cached grant so a
  /// REVOCATION is noticed too — app.dart calls it on every foreground resume.
  Future<bool> ensurePermission({bool allowPrompt = true}) async {
    if (_granted == true) return true;
    final request = debugRequestPermission;
    if (request == null) await init();

    if (_granted == false) {
      // Denied earlier in this process — re-read the OS rather than trusting a
      // stale no. Never re-prompts: once denied, both platforms no-op the
      // request anyway, and Settings is the only real path back.
      final live = await hasPermission();
      if (live) _granted = true;
      return live;
    }

    if (!allowPrompt) return hasPermission();

    bool granted;
    if (request != null) {
      granted = await request();
    } else {
      granted = true;
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        granted =
            await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        granted = await android.requestNotificationsPermission() ?? false;
      }
    }
    _granted = granted;
    return granted;
  }

  /// Drop the cached authorization decision so the next [ensurePermission] /
  /// [hasPermission] re-reads the live OS state. Called on every foreground
  /// resume (app.dart): the user may have flipped our notification switch
  /// either way in Settings while we were backgrounded.
  void invalidatePermissionCache() => _granted = null;

  /// Test seams for the platform permission plumbing (there is no plugin to
  /// talk to in a unit test). [debugRequestPermission] stands in for the
  /// interactive request, [debugProbePermission] for the non-prompting check.
  @visibleForTesting
  Future<bool> Function()? debugRequestPermission;
  @visibleForTesting
  Future<bool> Function()? debugProbePermission;

  /// Non-mutating: whether notifications are currently enabled, WITHOUT ever
  /// showing the OS authorization prompt. Safe to call from any context,
  /// including headless/background. Does not populate [_granted] — a
  /// not-yet-decided status here shouldn't get permanently cached as
  /// "denied" just because a background check happened to run first.
  Future<bool> hasPermission() async {
    try {
      final probe = debugProbePermission;
      if (probe != null) return await probe();
      await init();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null)
        return (await ios.checkPermissions())?.isEnabled ?? false;
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      return true; // other platforms (macOS/Linux) — no gating here
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _details(NotifCategory c) {
    final ch = _channelFor(c);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        ch.id,
        ch.name,
        channelDescription: ch.description,
        importance: _importanceFor(c),
        priority: _priorityFor(c),
        icon: '@mipmap/launcher_icon',
        // Device alerts reuse FIXED ids (idLowBattery/idCharging), so a re-post
        // is an UPDATE of a card the user is already looking at — it shouldn't
        // buzz again. Android only, and deliberately NOT load-bearing: the flag
        // suppresses sound only while a notification with that id is still
        // showing, so dismissing the card re-arms it. The real de-dupe lives in
        // DeviceAlerts/ChargeAlertPolicy; this just stops a redundant update
        // from making noise. iOS has no equivalent on DarwinNotificationDetails.
        onlyAlertOnce: c == NotifCategory.device,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// Present a NotificationEvent on its category channel. Same osId replaces, so
  /// re-firing the same logical event never stacks duplicates. Never throws.
  ///
  /// Returns true when the event was actually shown (permission granted, no
  /// error), false otherwise — [NotificationCenter.emit] uses this to record a
  /// key as fired only on a real present, so a permission-denied no-op doesn't
  /// permanently consume the dedupeKey.
  ///
  /// [allowPermissionPrompt] — see [ensurePermission]'s doc. Pass `false` from
  /// any caller that knows it's running headless/in the background.
  Future<bool> presentEvent(
    NotificationEvent e, {
    bool allowPermissionPrompt = true,
  }) async {
    try {
      if (!await ensurePermission(allowPrompt: allowPermissionPrompt)) {
        return false;
      }
      // Collision-free allocated id (NOT the old hashCode-modulo) — see
      // notification_ids.dart. Two same-category events used to be able to
      // share an id, and `show` REPLACES: one of them vanished silently.
      // e.osId overrides only for a caller that also cancels by id (see
      // NotificationEvent.osId).
      await _plugin.show(
        e.osId ?? await NotificationIds.instance.idFor(e),
        e.title,
        e.body.isEmpty ? null : e.body,
        _details(e.category),
        payload: e.route == null ? null : datedRoute(e.route!, e.date),
      );
      return true;
    } catch (_) {
      return false; /* best-effort */
    }
  }

  // ── Scheduling (wall-clock, OS-fired with no Dart running) ──────────────────

  tz.TZDateTime _nextInstanceOf(int hour, int minute, {int? weekday}) =>
      nextInstanceOf(
        tz.TZDateTime.now(tz.local),
        hour,
        minute,
        weekday: weekday,
      );

  /// The next [weekday] at [hour]:[minute] in local wall-clock time. For
  /// arming the lookback as a ONE-SHOT: a `dayOfWeekAndTime` repeat would go on
  /// re-firing the same week's finding every Sunday forever.
  DateTime nextWeeklyInstant(int weekday, int hour, int minute) =>
      _nextInstanceOf(hour, minute, weekday: weekday);

  /// Shared gate for every scheduled slot — see [schedulableIds].
  bool _maySchedule(int id) {
    if (maySchedule(id)) return true;
    debugPrint(
      '[notify] schedule refused for id $id — not an allow-listed '
      'scheduled slot',
    );
    return false;
  }

  Future<void> scheduleDaily({
    required int id,
    required NotifCategory category,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? route,
    bool skipToday = false,
    String? iosCategory,
  }) async {
    try {
      if (!_maySchedule(id)) return;
      if (!await ensurePermission(allowPrompt: false)) return;
      await ensureTimezone();
      var when = _nextInstanceOf(hour, minute);
      // skipToday: tonight's instance is already handled (e.g. the journal was
      // logged before the prompt time) — start the daily repeat tomorrow.
      if (skipToday) {
        final now = tz.TZDateTime.now(tz.local);
        if (when.year == now.year &&
            when.month == now.month &&
            when.day == now.day) {
          // Calendar day, not +24h — see nextInstanceOf's DST note.
          when = nextCalendarDay(when);
        }
      }
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        iosCategory == null
            ? _details(category)
            : NotificationDetails(
                android: _details(category).android,
                iOS: DarwinNotificationDetails(
                  categoryIdentifier: iosCategory,
                ),
              ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: route,
      );
    } catch (_) {}
  }

  /// True only when the repeat was handed to the system (Build 93, Codex
  /// full-flow audit C09): a caller showing "On" needs that, not just a
  /// granted permission.
  Future<bool> scheduleWeekly({
    required int id,
    required NotifCategory category,
    required String title,
    required String body,
    required int weekday, // DateTime.monday..sunday
    required int hour,
    required int minute,
    String? route,
  }) async {
    try {
      if (!_maySchedule(id)) return false;
      if (!await ensurePermission(allowPrompt: false)) return false;
      await ensureTimezone();
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOf(hour, minute, weekday: weekday),
        _details(category),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: route,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// One-shot absolute-time schedule (unlike [scheduleDaily]/[scheduleWeekly],
  /// no `matchDateTimeComponents` — this fires exactly once at [at] and is not
  /// re-armed by the plugin). Calling again with the same [id] before it fires
  /// replaces the pending instance (same "cancel, then reschedule" convention
  /// [scheduleStandingReminders] already uses for the recurring reminders).
  /// This is how the weekly lookback is armed — once, for a week that actually
  /// found something. (It also still carries the "time to move" nudge's call,
  /// which [schedulableIds] now refuses.)
  Future<void> scheduleOnce({
    required int id,
    required NotifCategory category,
    required String title,
    required String body,
    required DateTime at,
    String? route,
  }) async {
    try {
      if (!_maySchedule(id)) return;
      if (!await ensurePermission(allowPrompt: false)) return;
      final when = tz.TZDateTime.from(at, tz.local);
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details(category),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: route,
      );
    } catch (_) {}
  }

  /// A Pushups reminder at [at], in the Done/Pause category. Same gate as
  /// [scheduleOnce].
  Future<bool> schedulePushup({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required String payload,
  }) async {
    try {
      if (!_maySchedule(id)) return false;
      if (!await ensurePermission(allowPrompt: false)) return false;
      await ensureTimezone();
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        NotificationDetails(
          android: _details(NotifCategory.reminders).android,
          iOS: const DarwinNotificationDetails(
            categoryIdentifier: kPushupCategory,
            threadIdentifier: 'pushups',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ids of the requests iOS still holds; null when it cannot say.
  Future<Set<int>?> pendingIds() async {
    try {
      return {
        for (final r in await _plugin.pendingNotificationRequests()) r.id,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// Drop every notification this app has scheduled or posted.
  ///
  /// Part of "Delete everything": a scheduled alarm or wind-down reminder that
  /// survives a full reset fires days later, about data that is gone. The
  /// per-id [cancel] cannot reach them, because the ids live in the
  /// preferences the reset is clearing at the same time.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
