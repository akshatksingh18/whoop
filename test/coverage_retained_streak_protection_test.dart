// Current streak readers retain older protection metadata; no writer is revived.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2021, 4, 6, 18);
  setUpAll(() => coverageStore('retained-streak-protection', fresh: true));
  setUp(() async {
    await StepGoals.flush();
    await resetCoverageStore();
  });
  tearDown(() => StepGoals.flush());
  tearDownAll(LocalDb.close);
  final cases = <String, String>{
    'null': 'null',
    'list': '[]',
    'boolean': 'true',
    'number': '12',
    'string': '"authored old scalar"',
    'unreadable': '{authored unreadable',
    'unknown entries': jsonEncode({
      '2021-04-05': 'unknown',
      '2021-04-03': null,
      '2021-04-01': 2,
    }),
    'retained life and rest': jsonEncode({
      '2021-04-05': 'life',
      '2021-04-03': 'rest',
      '2021-04-01': 'unsupported',
    }),
  };
  for (final entry in cases.entries) {
    test(
      'Retained protection ${entry.key} never fabricates activity or rewrites history',
      () async {
        for (final ago in [0, 2, 4]) {
          final start =
              DateTime(
                at.year,
                at.month,
                at.day - ago,
                10,
              ).millisecondsSinceEpoch ~/
              1000;
          await LocalDb.putSession({
            'id': 'authored-walk-$ago',
            'start_ts': start,
            'type': 'walking',
            'status': 'done',
            'duration_min': 11,
            'source': 'manual',
            'created_at': 1,
          });
        }
        final baseline = (await loadMoveStreak(at: at))!;
        expect(baseline.todayDone, true);
        expect(baseline.last7[5], MoveDay.rest);
        await CalculationStore.write(StreakProtection.key, entry.value);
        await CalculationStore.write('authored-recovery', 'retain');
        final db = await LocalDb.instance;
        final sessions = await db.query('sessions');
        final anchors = await db.query('baselines');
        final ledger = await StreakProtection.read();
        final valid = entry.key == 'retained life and rest';
        expect(
          ledger,
          valid
              ? {'2021-04-05': Protection.life, '2021-04-03': Protection.rest}
              : isEmpty,
        );
        final actual = (await loadMoveStreak(at: at))!;
        expect(actual.current, baseline.current);
        expect(actual.longest, baseline.longest);
        expect(actual.todayDone, baseline.todayDone);
        expect(actual.protectedInStreak, baseline.protectedInStreak);
        expect(actual.last7[5], valid ? MoveDay.life : MoveDay.rest);
        expect(actual.last7[4], MoveDay.walk);
        expect(await CalculationStore.read(StreakProtection.key), entry.value);
        expect(await db.query('sessions'), sessions);
        expect(await db.query('baselines'), anchors);
        expect(await db.query('day_result'), isEmpty);
        expect(await db.query('live_coverage'), isEmpty);
        final again = await loadMoveStreak(at: at);
        expect(again!.current, actual.current);
        expect(again.longest, actual.longest);
        expect(again.todayDone, actual.todayDone);
        expect(again.protectedInStreak, actual.protectedInStreak);
        expect(again.last7, actual.last7);
        expect(await db.query('baselines'), anchors);
      },
    );
  }
}
