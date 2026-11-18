import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late String oldName;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('synthetic-step-history-');
    await LocalDb.close();
    oldName = LocalDb.dbName;
    LocalDb.dbName = '${root.path}/history.db';
    db = await LocalDb.instance;
  });
  tearDown(() async {
    DayClock.install([], []);
    await LocalDb.close();
    LocalDb.dbName = oldName;
    await root.delete(recursive: true);
  });
  Future<void> coverage(int start, int end, int steps) => db
      .insert('live_coverage', {
        'start_ts': start,
        'end_ts': end,
        'steps': steps,
        'source': LocalDb.kStepSourcePhone,
        'device_id': 'synthetic',
        'day': '2016-01-01',
      })
      .then((_) {});
  test(
    'batch history retains unmeasured points and resolves every spanned day',
    () async {
      final start = localDayStartSec('2016-01-01')!;
      final end = localDayEndSec('2016-01-03')!;
      await coverage(start, end, 7200);
      await coverage(
        localDayStartSec('2016-01-05')!,
        localDayEndSec('2016-01-05')!,
        0,
      );
      for (final d in ['2015-01-01', '2016-01-05']) {
        await db.insert('metric_series', {
          'date': d,
          'key': 'steps',
          'value': 77,
        });
      }
      final batch = await LocalDb.resolvedStepsByDay();
      for (final d in [
        '2016-01-01',
        '2016-01-02',
        '2016-01-03',
        '2016-01-05',
      ]) {
        final direct = await LocalDb.resolvedStepsForDay(d);
        expect(batch[d]!.total, direct.total);
        expect(batch[d]!.hasPhoneCoverage, direct.hasPhoneCoverage);
      }
      final chart = await LocalRepositoryImpl(
        getProfileMap: () => null,
      ).getChart('steps');
      final points = chart['points'] as List;
      final values = {
        for (final p in points) dayLabelAtSec(p['t'] as int): p['v'],
      };
      expect(values['2015-01-01'], 77);
      expect(values['2016-01-02'], 2400);
      expect(values['2016-01-05'], 0);
    },
  );
  test('single and batch step cuts share stored DST boundaries', () async {
    final start = DateTime.utc(2026, 3, 8, 5).millisecondsSinceEpoch ~/ 1000;
    final day = DayZone(
      date: '2026-03-08',
      zoneId: 'America/New_York',
      startSec: start,
      endSec: start + 23 * 3600,
      startOffsetSec: -5 * 3600,
      endOffsetSec: -4 * 3600,
    );
    DayClock.install([day], [ZoneChange(start, 'America/New_York')]);
    await coverage(start - 3600, start + 24 * 3600, 2500);
    final direct = await LocalDb.resolvedStepsForDay(day.date);
    final batch = await LocalDb.resolvedStepsByDay();
    expect(direct.total, 2300);
    expect(batch[day.date]!.total, direct.total);
  });
}
