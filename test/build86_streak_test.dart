// Activity streak edge cases (build 86, B86-10): late activity on a protected
// day, step-goal days beside protection, and the stored-session path that
// dedupes overlapping sessions and forgets a deleted one. Synthetic data.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/streak.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 3, 18);
  MoveSession on(int daysBack, int minutes) => (
    start: DateTime(now.year, now.month, now.day - daysBack, 7),
    minutes: minutes,
    kind: MoveKind.lift,
  );
  String back(int days) =>
      dayLabelOf(DateTime(now.year, now.month, now.day - days));

  test(
    'a workout that syncs onto a protected day counts as activity, once',
    () {
      final s = moveStreak(
        [on(0, 30), on(1, 30), on(2, 30)],
        now,
        protectedDays: {back(1): Protection.rest},
      );
      expect(s.current, 3);
      expect(s.protectedInStreak, 0, reason: 'the real lift replaces the rest');
      expect(s.last7[5], MoveDay.lift);
    },
  );

  test('a step-goal day and a protected day bridge together', () {
    final s = moveStreak(
      [on(0, 30)],
      now,
      stepDays: {back(1)},
      protectedDays: {back(2): Protection.life},
    );
    expect(s.current, 2);
    expect(s.protectedInStreak, 1);
    expect(s.last7[5], MoveDay.goal);
    expect(s.last7[4], MoveDay.life);
  });

  test('a protection with nothing either side keeps no streak alive', () {
    final s = moveStreak(
      const [],
      now,
      protectedDays: {back(1): Protection.rest},
    );
    expect(s.current, 0);
    expect(s.longest, 0, reason: 'protection is never an activity day');
  });

  group('stored sessions', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'build86_streak_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });
    tearDownAll(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> session(String id, String type, DateTime s, int min) async {
      final db = await LocalDb.instance;
      int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
      await db.insert('sessions', {
        'id': id,
        'type': type,
        'status': 'done',
        'start_ts': sec(s),
        'end_ts': sec(s.add(Duration(minutes: min))),
        'created_at': sec(s),
      });
    }

    test('overlapping sessions count their shared minutes once', () async {
      final t = DateTime.now();
      final at = DateTime(t.year, t.month, t.day - 1, 7);
      // Two 8-minute records of the same 8 minutes: 8 unique, not 16.
      await session('dup-a', 'Weight training', at, 8);
      await session('dup-b', 'Weight training', at, 8);
      final s = (await loadMoveStreak())!;
      expect(s.last7[5], MoveDay.none);
      // A separate 4 minutes the same morning reaches ten.
      await session(
        'dup-c',
        'Weight training',
        at.add(const Duration(minutes: 20)),
        4,
      );
      expect((await loadMoveStreak())!.last7[5], MoveDay.lift);
    });

    test('a deleted session no longer earns its day', () async {
      final t = DateTime.now();
      final at = DateTime(t.year, t.month, t.day - 2, 7);
      await session('del-a', 'Running', at, 30);
      expect((await loadMoveStreak())!.last7[4], MoveDay.run);
      await LocalDb.deleteSession('del-a');
      expect((await loadMoveStreak())!.last7[4], MoveDay.none);
    });
  });
}
