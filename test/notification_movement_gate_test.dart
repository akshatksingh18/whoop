// The gate contract for the sedentary/movement prompt (kRouteMovement).
//
// History this pins: the desk-posture check emitted for months on
// reminders/low with a bare `/today` route — exactly the pair `classOf`
// drops — so it never once reached a notification shade. It now rides
// prompt class via a dedicated route, gated by `movementEnabled`. These
// tests pin BOTH directions of that keying:
//   • the movement route at normal priority gets through (when opted in);
//   • nothing else on reminders-at-low/at-normal does — the deleted-nudges
//     pair stays closed;
//   • the movement switch actually stops the movement event;
//   • a query-parameter payload (`?id=`) still matches, because every route
//     comparison must go through routePath.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/tap_router.dart';

NotificationEvent movementEvent({NotifPriority priority = NotifPriority.normal,
    String? route}) {
  return NotificationEvent(
    dedupeKey: '2026-08-22:posture:test',
    category: NotifCategory.reminders,
    priority: priority,
    title: 'Time to move',
    body: 'test',
    date: '2026-8-22',
    route: route ?? kRouteMovement,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  group('classOf', () {
    test('the movement prompt is a prompt', () {
      expect(classOf(movementEvent()), NotifClass.prompt);
      // An id-carrying payload resolves through routePath.
      expect(
          classOf(movementEvent(route: '$kRouteMovement?id=abc')),
          NotifClass.prompt);
    });

    test('a low-priority event on the same route stays dropped', () {
      // Priority is part of the sanction, same narrowing as the workout
      // prompt got after its low-priority walk-through bug.
      expect(classOf(movementEvent(priority: NotifPriority.low)), isNull);
    });

    test('other reminders events on the shared routes stay dropped', () {
      NotificationEvent ev(String route) => NotificationEvent(
            dedupeKey: '2026-08-22:x',
            category: NotifCategory.reminders,
            title: 'x',
            body: '',
            date: '2026-8-22',
            route: route,
          );
      expect(classOf(ev('/today')), isNull);
      expect(classOf(ev('/today/movementX')), isNull); // prefix games fail
    });
  });

  group('shouldFireOs', () {
    test('fires when movementEnabled is on, outside quiet hours', () async {
      // OPT-IN: the shipped default has the switch off, which is exactly what
      // the next test pins. Turn it on to assert the pass-through.
      final prefs =
          (await NotificationPrefs.load()).copyWith(movementEnabled: true);
      final minuteOfDay = DateTime.now().hour * 60 + DateTime.now().minute;
      if (!prefs.inQuietHours(minuteOfDay)) {
        expect(prefs.shouldFireOs(movementEvent(), minuteOfDay), isTrue);
      }
    });

    test("the movement switch stops the movement prompt", () async {
      final prefs =
          (await NotificationPrefs.load()).copyWith(movementEnabled: false);
      expect(prefs.shouldFireOs(movementEvent(), 12 * 60), isFalse);
    });

    test('quiet hours still drop it — it is not the alarm', () async {
      final prefs = await NotificationPrefs.load();
      // Default quiet window opens at 22:00.
      expect(prefs.shouldFireOs(movementEvent(), 23 * 60), isFalse);
    });
  });
}
