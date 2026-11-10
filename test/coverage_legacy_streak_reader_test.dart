// Actual older session rows, with recorded minutes rather than invented end times.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2021, 4, 6, 18);
  final morning = DateTime(2021, 4, 6, 8).millisecondsSinceEpoch ~/ 1000;
  setUpAll(() => coverageStore('legacy-streak-reader'));
  setUp(() async {
    await StepGoals.flush();
    await resetCoverageStore();
  });
  tearDown(() => StepGoals.flush());
  tearDownAll(LocalDb.close);

  Future<void> row(
    String id, {
    int minutes = 10,
    int? end,
    int? start,
    String? type = 'walking',
    String status = 'done',
    int fabricated = 0,
  }) async {
    await (await LocalDb.instance).insert('sessions', {
      'id': id,
      'start_ts': start ?? morning,
      'end_ts': end,
      'type': type,
      'status': status,
      'duration_min': minutes,
      'end_ts_fabricated': fabricated,
      'created_at': 1,
    });
  }

  Future<List<Map<String, Object?>>> sessions() async =>
      (await LocalDb.instance).query('sessions', orderBy: 'id');

  for (final minutes in [0, 9, 10, 11]) {
    test(
      'legacy $minutes recorded minutes honors the existing ten-minute boundary without adding an end',
      () async {
        await row('authored-legacy', minutes: minutes);
        final before = await sessions();
        final result = await loadMoveStreak(at: now);
        expect(result, isNotNull);
        expect(result!.todayDone, minutes >= 10);
        expect(result.last7.last, minutes >= 10 ? MoveDay.walk : MoveDay.none);
        expect(await sessions(), before);
        expect((await sessions()).single['end_ts'], isNull);
        expect(await (await LocalDb.instance).query('day_result'), isEmpty);
      },
    );
  }

  for (final fabricated in [false, true]) {
    test(
      'recorded legacy minutes survive ${fabricated ? 'a fabricated end' : 'a reversed window'} without trusting its span',
      () async {
        await row(
          'authored-legacy',
          minutes: 9,
          end: fabricated ? morning + 3600 : morning - 60,
          fabricated: fabricated ? 1 : 0,
        );
        final before = await sessions();
        final result = await loadMoveStreak(at: now);
        expect(
          result!.todayDone,
          false,
          reason:
              'Nine recorded minutes must not become an invented one-hour exercise.',
        );
        expect(await sessions(), before);
      },
    );
  }

  test(
    'separate legacy bouts combine recorded minutes and keep the strongest real activity kind',
    () async {
      await row('authored-walk', minutes: 6);
      await row(
        'authored-run',
        minutes: 5,
        type: 'running',
        start: morning + 1800,
      );
      final before = await sessions();
      final result = await loadMoveStreak(at: now);
      expect(result!.todayDone, true);
      expect(result.last7.last, MoveDay.run);
      expect(await sessions(), before);
    },
  );

  for (final excluded in ['live', 'meditation']) {
    test(
      '$excluded evidence cannot top up an incomplete legacy exercise day',
      () async {
        await row('authored-walk', minutes: 6);
        await row(
          'authored-excluded',
          minutes: 30,
          start: morning + 3600,
          type: excluded == 'meditation' ? 'meditation' : 'running',
          status: excluded == 'live' ? 'live' : 'done',
        );
        final before = await sessions();
        final result = await loadMoveStreak(at: now);
        expect(result!.todayDone, false);
        expect(await sessions(), before);
      },
    );
  }

  test(
    'a missing stored type is refused without counting its minutes',
    () async {
      await row('authored-walk', minutes: 6);
      final before = await sessions();
      await expectLater(
        row('authored-missing-type', minutes: 30, type: null),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.toString(),
            'required identity',
            contains('NOT NULL constraint failed: sessions.type'),
          ),
        ),
      );
      expect(await sessions(), before);
      expect((await loadMoveStreak(at: now))!.todayDone, false);
    },
  );

  test('a retained future-dated row cannot earn the current day', () async {
    await row('authored-future', minutes: 30, start: morning + 86400);
    final before = await sessions();
    final result = await loadMoveStreak(at: now);
    expect(result!.todayDone, false);
    expect(result.current, 0);
    expect(await sessions(), before);
  });

  test(
    'a refused session read reports unknown and a restored reader retries without repairing history',
    () async {
      await row('authored-legacy');
      final before = await sessions();
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE sessions RENAME TO authored_retained_sessions',
      );
      try {
        expect(await loadMoveStreak(at: now), isNull);
      } finally {
        await db.execute(
          'ALTER TABLE authored_retained_sessions RENAME TO sessions',
        );
      }
      expect((await loadMoveStreak(at: now))!.todayDone, true);
      expect(await sessions(), before);
    },
  );

  test(
    'an unreadable profile does not erase known session minutes or invent new scores',
    () async {
      await row('authored-legacy');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_profile_json', '{authored-unreadable');
      final before = await sessions();
      expect((await loadMoveStreak(at: now))!.todayDone, true);
      expect(await sessions(), before);
      expect(prefs.getString('local_profile_json'), '{authored-unreadable');
      expect(await (await LocalDb.instance).query('day_result'), isEmpty);
    },
  );
}
