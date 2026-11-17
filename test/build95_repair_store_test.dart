// Small store-level regressions; all dates and measurements are synthetic.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/tap_router.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final log = NotificationLog.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    log.clock = () => DateTime(2026, 10, 21, 22);
    await log.clear();
  });
  tearDown(() {
    log.clock = DateTime.now;
    DayClock.install([], []);
  });
  test(
    'an old repeating plan catches up within retention without replaying years',
    () async {
      await log.plan(
        id: 95,
        first: DateTime(2024, 1, 1, 21, 30),
        repeat: PlanRepeat.daily,
        title: 'Synthetic food reminder',
        body: 'Review this day',
        category: 'reminders',
        route: '/food',
      );
      final entries = await log.entries();
      expect(entries, hasLength(90));
      expect(routeDay(entries.first.route!), '2026-10-21');
      expect(routePath(entries.first.route!), kRouteFoodDay);
    },
  );
  test(
    'reconciling unchanged history hydrates unread without a revision loop',
    () async {
      final p = await SharedPreferences.getInstance();
      final entry = LoggedNotification(
        key: 'synthetic',
        at: DateTime(2026, 10, 21, 20),
        title: 'Synthetic',
        body: '',
        category: 'reminders',
      );
      await p.setString('notify.log', jsonEncode([entry.toJson()]));
      log.unread.value = 0;
      await log.reconcile();
      expect(log.unread.value, 1);
      final revision = log.revision.value;
      await log.entries();
      await log.entries();
      expect(log.revision.value, revision);
    },
  );
  test('tape selection is deterministic even with identical timestamps', () {
    final at = DateTime(2026, 9, 1, 8);
    final a = BodyMeasure(
      id: 'synthetic-a',
      date: '2026-09-01',
      recordedAt: at,
      inches: {BodySite.waistNavel.name: 34},
    );
    final b = BodyMeasure(
      id: 'synthetic-b',
      date: '2026-09-01',
      recordedAt: at,
      inches: {BodySite.waistNavel.name: 35},
    );
    expect(siteSeries([a, b], BodySite.waistNavel).single.value, 35);
    expect(siteSeries([b, a], BodySite.waistNavel).single.value, 35);
  });
  test('stored-zone wall times keep the DST night length', () {
    final zone = dayZoneLocation('America/Chicago');
    final reference = tz.TZDateTime(zone, 2026, 3, 7, 23);
    final start = DayClock.wallTime(reference, 2026, 3, 7, 23, 0);
    final end = DayClock.wallTime(reference, 2026, 3, 8, 7, 0);
    expect(end.difference(start), const Duration(hours: 7));
    expect(start.timeZoneOffset, const Duration(hours: -6));
    expect(end.timeZoneOffset, const Duration(hours: -5));
  });
}
