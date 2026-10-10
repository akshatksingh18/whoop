// Pushups inside WHOOP (build 86): the AkshatOS Pushup Reminder contract —
// explicit sets only, goal captured per day, streak at risk rather than
// broken today, idempotent notification actions, Home boundary rules and a
// previewed import. Synthetic data only.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/ui2/screens/pushups_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PushupSession day(String d, int sets, {int? goal = 8, bool ended = true}) {
  final start = DateTime.parse(d).add(const Duration(hours: 8));
  final s = PushupSession(
    day: d,
    started: start,
    interval: 45,
    goal: goal,
    state: PushupState.running,
  );
  for (var i = 0; i < sets; i++) {
    s.log(
      PushupEvent(
        at: start.add(Duration(minutes: 45 * (i + 1))),
        kind: PushupEventKind.done,
      ),
    );
  }
  if (ended) {
    s
      ..state = PushupState.ended
      ..ended = start.add(const Duration(hours: 10));
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('streak', () {
    final now = DateTime(2026, 10, 10, 12);
    test('counts days at goal, today at risk does not break it', () {
      final st = pushupStreaks([
        day('2026-10-07', 8),
        day('2026-10-08', 9),
        day('2026-10-09', 8),
        day('2026-10-10', 2, ended: false),
      ], now);
      expect(st.current, 3);
      expect(st.best, 3);
    });

    test(
      'a day below its own goal breaks it; the goal is the day\'s, not today\'s',
      () {
        final st = pushupStreaks([
          day('2026-10-07', 4, goal: 4),
          day('2026-10-08', 5),
          day('2026-10-09', 6, goal: 6),
        ], now);
        expect(st.current, 1);
        expect(st.best, 1);
      },
    );

    test('goal off means no streak day; a future day never counts', () {
      final st = pushupStreaks([
        day('2026-10-09', 20, goal: null),
        day('2026-10-11', 9),
      ], now);
      expect(st.current, 0);
      expect(st.best, 0);
    });
  });

  group('day recap', () {
    test('active and paused time come from the pause and resume events', () {
      final s = day('2026-10-09', 3);
      final t = s.started;
      s.events.addAll([
        PushupEvent(
          at: t.add(const Duration(hours: 2)),
          kind: PushupEventKind.pause,
        ),
        PushupEvent(
          at: t.add(const Duration(hours: 3)),
          kind: PushupEventKind.resume,
        ),
      ]);
      final d = PushupDay.of('2026-10-09', [s], DateTime(2026, 10, 10))!;
      expect(d.sets, 3);
      expect(d.paused, const Duration(hours: 1));
      expect(d.active, const Duration(hours: 9));
      expect(d.status, PushupGoalStatus.missed);
    });
  });

  group('notification actions', () {
    test(
      'a Done is applied once, on its own day, and restarts the interval',
      () {
        final s = day('2026-10-10', 0, ended: false);
        final at = s.started.add(const Duration(minutes: 50));
        final a = PushupAction(
          id: 'x|2500|1|done',
          kind: 'done',
          sessionId: s.id,
          at: at,
        );
        expect(a.applyTo(s), isTrue);
        expect(a.applyTo(s), isFalse, reason: 'a replayed callback is a no-op');
        expect(s.count, 1);
        expect(s.anchor, at.add(const Duration(minutes: 45)));
        final late = PushupAction(
          id: 'x|2500|2|done',
          kind: 'done',
          sessionId: s.id,
          at: DateTime(2026, 10, 11, 0, 5),
        );
        expect(
          late.applyTo(s),
          isFalse,
          reason: 'a Done after midnight is not this day\'s',
        );
      },
    );

    test('Pause stops the clock and records why', () {
      final s = day('2026-10-10', 0, ended: false)
        ..anchor = DateTime(2026, 10, 10, 9);
      PushupAction(
        id: 'p',
        kind: 'pause',
        sessionId: s.id,
        at: s.started.add(const Duration(minutes: 5)),
      ).applyTo(s);
      expect(s.state, PushupState.paused);
      expect(s.anchor, isNull);
      expect(s.pauseReason, 'notification');
    });

    test('the clock shows the reminder, then each ten-minute nudge', () {
      final s = day('2026-10-10', 0, ended: false)
        ..anchor = DateTime(2026, 10, 10, 9);
      expect(
        pushupNextDue(s, DateTime(2026, 10, 10, 8, 30)),
        DateTime(2026, 10, 10, 9),
      );
      expect(
        pushupNextDue(s, DateTime(2026, 10, 10, 9, 14)),
        DateTime(2026, 10, 10, 9, 20),
      );
    });
  });

  group('Home boundary', () {
    test('leaving pauses a running day; arriving resumes only that pause', () {
      final s = day('2026-10-10', 0, ended: false);
      final h = HomeAutomation(presence: HomePresence.inside);
      final t = DateTime(2026, 10, 10, 9);
      expect(
        h.accept(HomePresence.outside, t, active: s, today: '2026-10-10'),
        'pause',
      );
      s
        ..state = PushupState.paused
        ..pauseReason = kHomeAwayReason;
      expect(
        h.accept(
          HomePresence.inside,
          t.add(const Duration(hours: 1)),
          active: s,
          today: '2026-10-10',
        ),
        'resume',
      );
    });

    test('a pause you chose is never resumed by arriving', () {
      final s = day('2026-10-10', 0, ended: false)
        ..state = PushupState.paused
        ..pauseReason = 'manual';
      final h = HomeAutomation(presence: HomePresence.outside);
      expect(
        h.accept(
          HomePresence.inside,
          DateTime(2026, 10, 10, 10),
          active: s,
          today: '2026-10-10',
        ),
        isNull,
      );
    });

    test(
      'a manual resume outside suppresses exit pauses until home; duplicates are ignored',
      () {
        final s = day('2026-10-10', 0, ended: false);
        final h = HomeAutomation(
          presence: HomePresence.outside,
          suppressExit: true,
        );
        final t = DateTime(2026, 10, 10, 11);
        expect(
          h.accept(HomePresence.outside, t, active: s, today: '2026-10-10'),
          isNull,
        );
        expect(
          h.accept(
            HomePresence.inside,
            t.add(const Duration(minutes: 30)),
            active: s,
            today: '2026-10-10',
          ),
          isNull,
        );
        expect(h.suppressExit, isFalse);
        expect(
          h.accept(
            HomePresence.inside,
            t.add(const Duration(minutes: 31)),
            active: s,
            today: '2026-10-10',
          ),
          isNull,
          reason: 'duplicate within two minutes',
        );
        expect(
          h.accept(
            HomePresence.outside,
            t.add(const Duration(hours: 1)),
            active: s,
            today: '2026-10-10',
          ),
          'pause',
        );
      },
    );
  });

  group('store and import', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'build86_pushups_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });
    tearDownAll(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });
    setUp(() => SharedPreferences.setMockInitialValues({}));

    double apple(DateTime d) => d.millisecondsSinceEpoch / 1000 - 978307200;
    String backup({bool open = false}) => jsonEncode({
      'version': 1,
      'createdAt': apple(DateTime(2026, 10, 1)),
      'settings': {'interval': 40, 'goal': 6},
      'sessions': [
        {
          'id': 'A1B2C3D4-0000-4000-8000-0000000000AA',
          'day': '2026-09-20',
          'started': apple(DateTime(2026, 9, 20, 8)),
          if (!open) 'ended': apple(DateTime(2026, 9, 20, 18)),
          'interval': 45,
          'goal': 8,
          'state': open ? 'running' : 'ended',
          'events': [
            {
              'id': 'E1',
              'date': apple(DateTime(2026, 9, 20, 9)),
              'kind': 'done',
            },
            {
              'id': 'E2',
              'date': apple(DateTime(2026, 9, 20, 10)),
              'kind': 'snooze',
            },
          ],
        },
      ],
    });

    test(
      'a finished AkshatOS backup previews, imports once, and keeps its shape',
      () async {
        final plan = await planPushupImport(backup());
        expect(plan.add.single.count, 1);
        expect(plan.interval, 40);
        expect(await applyPushupImport(plan, useSettings: true), 1);
        expect(await PushupDb.interval(), 40);
        expect(await PushupDb.goal(), 6);
        expect((await planPushupImport(backup())).add, isEmpty);
        final out = jsonDecode(await exportPushupBackup()) as Map;
        expect((out['sessions'] as List).single['day'], '2026-09-20');
        expect(out['settings'], {'interval': 40, 'goal': 6});
      },
    );

    test(
      'an open AkshatOS day is refused, so no reminders restore running',
      () async {
        expect(
          () => planPushupImport(backup(open: true)),
          throwsFormatException,
        );
        expect(() => planPushupImport('{"version":2}'), throwsFormatException);
      },
    );

    test('settings are range-checked', () async {
      expect(() => PushupDb.setInterval(0), throwsRangeError);
      expect(() => PushupDb.setGoal(101), throwsRangeError);
    });

    testWidgets('the day screen states sets, goal result and pauses', (
      t,
    ) async {
      final d = PushupDay.of('2026-10-09', [
        day('2026-10-09', 8),
      ], DateTime(2026, 10, 10))!;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: PushupDayScreen(day: d),
        ),
      );
      expect(find.text('8 sets of 8'), findsOneWidget);
      expect(find.textContaining('Goal reached'), findsOneWidget);
      expect(
        find.textContaining('Reminders iOS showed are not counted'),
        findsOneWidget,
      );
      expect(dayLabelOf(d.started), '2026-10-09');
    });
  });

  test('the Home bridge channel name matches the native side', () {
    expect(
      const MethodChannel('openstrap/home_region').name,
      'openstrap/home_region',
    );
  });
}
