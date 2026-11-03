// Real notification plans/history with authored preferences, not OS delivery.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/notification_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final log = NotificationLog.instance;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2021, 4, 6, 12);
    log.clock = () => now;
    await log.clear();
  });
  tearDown(() => log.clock = DateTime.now);

  test(
    'weekly occurrences exclude the lower endpoint and include the due minute',
    () {
      final first = DateTime(2020, 12, 29, 9, 25);
      expect(
        NotificationLog.occurrences(
          first,
          PlanRepeat.weekly,
          DateTime(2021, 1, 5, 9, 25),
          DateTime(2021, 1, 19, 9, 25),
        ),
        [DateTime(2021, 1, 12, 9, 25), DateTime(2021, 1, 19, 9, 25)],
      );
    },
  );

  test(
    'weekly jump retains the original weekday and minute after a long absence',
    () {
      final first = DateTime(2019, 12, 31, 7, 35);
      final occurrences = NotificationLog.occurrences(
        first,
        PlanRepeat.weekly,
        DateTime(2021, 4, 7),
        DateTime(2021, 4, 21),
      );
      expect(occurrences, [
        DateTime(2021, 4, 13, 7, 35),
        DateTime(2021, 4, 20, 7, 35),
      ]);
      expect(occurrences.every((d) => d.weekday == DateTime.tuesday), isTrue);
    },
  );

  test(
    'daily occurrences preserve wall minute across year and leap-day boundaries',
    () {
      expect(
        NotificationLog.occurrences(
          DateTime(2020, 2, 28, 23, 45),
          PlanRepeat.daily,
          DateTime(2020, 2, 28, 23, 45),
          DateTime(2020, 3, 1, 23, 45),
        ),
        [DateTime(2020, 2, 29, 23, 45), DateTime(2020, 3, 1, 23, 45)],
      );
      expect(
        NotificationLog.occurrences(
          DateTime(2020, 12, 31, 23, 45),
          PlanRepeat.daily,
          DateTime(2020, 12, 31, 23, 45),
          DateTime(2021, 1, 1, 23, 44),
        ),
        isEmpty,
      );
    },
  );

  test(
    'once plans do not invent an occurrence outside the open-closed window',
    () {
      final first = DateTime(2021, 4, 6, 10);
      expect(
        NotificationLog.occurrences(first, PlanRepeat.once, first, now),
        isEmpty,
      );
      expect(
        NotificationLog.occurrences(
          first,
          PlanRepeat.once,
          first.subtract(const Duration(seconds: 1)),
          first,
        ),
        [first],
      );
      expect(
        NotificationLog.occurrences(
          first,
          PlanRepeat.once,
          first.subtract(const Duration(hours: 2)),
          first.subtract(const Duration(seconds: 1)),
        ),
        isEmpty,
      );
    },
  );

  test(
    'weekly reconciliation and cancellation preserve each fired occurrence once',
    () async {
      await log.plan(
        id: 55,
        first: DateTime(2021, 4, 6, 14, 15),
        repeat: PlanRepeat.weekly,
        title: 'Authored weekly notice',
        body: 'Keep this body',
        category: 'reminders',
        route: '/recap',
      );
      now = DateTime(2021, 4, 20, 14, 15);
      await log.reconcile();
      await log.reconcile();
      final before = await log.entries();
      expect(before.map((e) => e.at), [
        DateTime(2021, 4, 20, 14, 15),
        DateTime(2021, 4, 13, 14, 15),
        DateTime(2021, 4, 6, 14, 15),
      ]);
      expect(before.map((e) => e.key).toSet(), hasLength(3));
      expect(
        before.every(
          (e) =>
              e.origin == NotificationOrigin.scheduled &&
              e.body == 'Keep this body' &&
              e.route == '/recap',
        ),
        isTrue,
      );
      await log.unplan(55);
      now = DateTime(2021, 4, 27, 15);
      await log.reconcile();
      expect(
        (await log.entries()).map((e) => e.toJson()),
        before.map((e) => e.toJson()),
      );
    },
  );

  test(
    'opening general food marks only the newest dated food notice read',
    () async {
      await log.record(
        title: 'Older dated food',
        body: 'Older body',
        category: 'reminders',
        route: '/food/day?day=2021-04-04',
        at: now.subtract(const Duration(hours: 2)),
      );
      await log.record(
        title: 'Newer dated food',
        body: 'Newer body',
        category: 'reminders',
        route: '/food/day?day=2021-04-05',
        at: now.subtract(const Duration(hours: 1)),
      );
      await log.record(
        title: 'Other notice',
        body: 'Other body',
        category: 'health',
        route: '/body',
      );
      await log.markRouteRead('/food');
      final rows = await log.entries();
      expect(
        rows.singleWhere((e) => e.title == 'Newer dated food').read,
        isTrue,
      );
      expect(rows.where((e) => e.read), hasLength(1));
      final before = rows.map((e) => e.toJson()).toList();
      await log.markRouteRead('/unknown-route');
      expect((await log.entries()).map((e) => e.toJson()), before);
      expect(log.unread.value, 2);
    },
  );
}
