// The gate contract for the forgotten-workout nudge (kRouteWorkoutIdle).
//
// Same shape as the movement prompt's gate test, and for the same reason: the
// reminders-at-normal pair is exactly the pair every one of the deleted
// nudges would arrive on, so a new event on it must be sanctioned by ROUTE,
// and both directions of that keying are worth pinning — the idle route gets
// through, and nothing else rides in with it. Unlike the movement prompt this
// one has no switch of its own: it reports on a session the USER started (a
// measured quiet stretch inside it), so the reminders category toggle is its
// off switch, the same way recovery-ready rides recoveryEnabled.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/tap_router.dart';

NotificationEvent idleEvent(
    {NotifPriority priority = NotifPriority.normal, String? route}) {
  return NotificationEvent(
    dedupeKey: 'w123:workout_idle',
    category: NotifCategory.reminders,
    priority: priority,
    title: 'Still working out?',
    body: 'test',
    date: '2026-08-25',
    route: route ?? kRouteWorkoutIdle,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  group('classOf', () {
    test('the idle nudge is a prompt', () {
      expect(classOf(idleEvent()), NotifClass.prompt);
      // An id-carrying payload resolves through routePath.
      expect(classOf(idleEvent(route: '$kRouteWorkoutIdle?id=w123')),
          NotifClass.prompt);
    });

    test('a low-priority event on the same route stays dropped', () {
      expect(classOf(idleEvent(priority: NotifPriority.low)), isNull);
    });

    test('other reminders events do not ride in on the new sanction', () {
      NotificationEvent ev(String route) => NotificationEvent(
            dedupeKey: '2026-08-25:x',
            category: NotifCategory.reminders,
            title: 'x',
            body: '',
            date: '2026-08-25',
            route: route,
          );
      expect(classOf(ev('/workouts')), isNull);
      expect(classOf(ev('${kRouteWorkoutIdle}X')), isNull); // prefix games fail
    });
  });

  group('shouldFireOs', () {
    test('fires by default outside quiet hours — reminders default on', () async {
      final prefs = await NotificationPrefs.load();
      expect(prefs.shouldFireOs(idleEvent(), 12 * 60), isTrue);
    });

    test('the reminders category toggle is its off switch', () async {
      final prefs =
          (await NotificationPrefs.load()).copyWith(remindersEnabled: false);
      expect(prefs.shouldFireOs(idleEvent(), 12 * 60), isFalse);
    });

    test('quiet hours drop it — it is not the alarm', () async {
      final prefs = await NotificationPrefs.load();
      // Default quiet window opens at 22:00. The emit site retries, so a
      // dropped overnight ask becomes the morning nudge rather than a loss.
      expect(prefs.shouldFireOs(idleEvent(), 23 * 60), isFalse);
    });
  });

  test('the tap lands on the Workouts tab, where the live session bar is', () {
    final t = resolveTapRoute(kRouteWorkoutIdle);
    expect(t.tab, 4);
    expect(t.screen, isNull,
        reason: 'the tab IS the destination — this route has no sub-screen '
            'to push (app.dart\'s screenForRoute answers null for it), so it '
            'is a tab route, not a screen route');
  });
}
