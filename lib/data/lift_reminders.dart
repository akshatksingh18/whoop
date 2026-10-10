// Lift Log's OS-scheduled reminders (build 86): the one-hour inactivity ask
// and the optional rest timer. Kept out of lib/ui2: they are scheduling, not
// motion, so the reduced-motion Duration rule does not apply to them.

import 'package:shared_preferences/shared_preferences.dart';

import '../notify/notification_event.dart';
import '../notify/notification_service.dart';
import '../notify/tap_router.dart' show kRouteWorkoutIdle, datedRoute;
import 'day_label.dart' show todayLabel;
import 'lift_log.dart';

// ── reminders: inactivity and rest ─────────────────────────────────────────

/// Lift Log's one-hour "Still working out?" and the optional rest timer, as
/// OS-scheduled one-shots so they arrive while the app is suspended. While a
/// session has a set log, this replaces the 20-minute heart-rate quiet nudge
/// (one coordinated policy, never two asks).
class LiftReminders {
  LiftReminders._();

  /// Sessions whose forgotten-workout ask belongs to this file.
  static final Set<String> loggingSessions = {};

  static Future<void> update(LiftWorkout w) async {
    final id = w.sessionId;
    if (id == null || !w.isActive) return cancel();
    loggingSessions.add(id);
    final due = w.lastActivity.add(LiftWorkout.inactivityDelay);
    final now = DateTime.now();
    await NotificationService.instance.scheduleOnce(
      id: NotificationService.idLiftInactivity,
      category: NotifCategory.reminders,
      title: 'Still working out?',
      body:
          'Nothing logged for an hour. Open the workout to finish it now or '
          'at your last set.',
      at: due.isAfter(now) ? due : now.add(LiftWorkout.inactivityDelay),
      route: datedRoute(kRouteWorkoutIdle, todayLabel(), id: id),
    );
  }

  static Future<void> cancel() async {
    loggingSessions.clear();
    await NotificationService.instance.cancel(
      NotificationService.idLiftInactivity,
    );
    await RestTimer.skip();
  }
}

/// A rest countdown held as a durable deadline, not a running process: the
/// lock screen or a relaunch shows the right remaining time, and the alert
/// is an OS one-shot. It never pauses the WHOOP session.
class RestTimer {
  RestTimer._();
  static const _deadlineKey = 'lift.rest.deadline';
  static const _defaultKey = 'lift.rest.default_sec';
  static const _perKey = 'lift.rest.per.';

  /// Choices offered; 0 is Off.
  static const choices = [0, 60, 90, 120, 180];

  static Future<SharedPreferences?> _p() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<int> defaultSec() async =>
      (await _p())?.getInt(_defaultKey) ?? 0;

  static Future<void> setDefault(int sec) async =>
      (await _p())?.setInt(_defaultKey, sec);

  static Future<int> forExercise(String name) async {
    final p = await _p();
    return p?.getInt('$_perKey${liftNameKey(name)}') ??
        p?.getInt(_defaultKey) ??
        0;
  }

  static Future<void> setForExercise(String name, int? sec) async {
    final p = await _p();
    if (sec == null) {
      await p?.remove('$_perKey${liftNameKey(name)}');
    } else {
      await p?.setInt('$_perKey${liftNameKey(name)}', sec);
    }
  }

  static Future<DateTime?> deadline() async {
    final ms = (await _p())?.getInt(_deadlineKey);
    if (ms == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return d.isAfter(DateTime.now()) ? d : null;
  }

  static Future<void> start(int sec, {String? sessionId}) async {
    if (sec <= 0) return;
    final d = DateTime.now().add(Duration(seconds: sec));
    await (await _p())?.setInt(_deadlineKey, d.millisecondsSinceEpoch);
    await NotificationService.instance.scheduleOnce(
      id: NotificationService.idRestTimer,
      category: NotifCategory.reminders,
      title: 'Rest is up',
      body: 'Time for the next set.',
      at: d,
      route: sessionId == null
          ? null
          : datedRoute(kRouteWorkoutIdle, todayLabel(), id: sessionId),
    );
  }

  static Future<void> addSeconds(int extra, {String? sessionId}) async {
    final d = await deadline();
    if (d == null) return;
    final left = d.difference(DateTime.now()) + Duration(seconds: extra);
    await start(left.inSeconds, sessionId: sessionId);
  }

  static Future<void> skip() async {
    await (await _p())?.remove(_deadlineKey);
    await NotificationService.instance.cancel(NotificationService.idRestTimer);
  }
}

