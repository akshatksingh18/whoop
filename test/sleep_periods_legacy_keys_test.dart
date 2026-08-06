// SCHEMA-DRIFT REGRESSION — Sleep-periods cards for days derived BEFORE the
// period key rename.
//
// The producer used to write `start`/`end`/`asleep_min`; it now writes
// `onset_ts`/`wake_ts`/`duration_min`, which is what the screen reads.
//
// Old rows are NOT re-derived into the new shape. A day finalizes ~48 h behind
// the data edge and raw is pruned after `rawRetentionDays`, so once its
// substrate is gone a kAlgoVersion bump cannot recompute it — `dayResult()`
// keeps serving that stored payload forever. Without a read-side translation
// every such day renders "—" for onset, wake AND duration on every card,
// underneath a hero total that is still confident: it reads as data loss
// rather than as an old schema.
//
// Doing this on READ rather than as a write migration is also what makes this
// fix independent of the ordering of the two PRs touching this seam.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

void main() {
  late LocalRepositoryImpl repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_periods_legacy_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    repo = LocalRepositoryImpl(getProfileMap: () => const {});
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  setUp(() async {
    final db = await LocalDb.instance;
    await db.delete('day_result');
    await db.delete('metric_series');
  });

  const onset = 1750000000;
  const wake = onset + 7 * 3600;
  const napOnset = onset + 14 * 3600;
  const napWake = napOnset + 40 * 60;

  Future<void> seed(Map<String, dynamic> sleepPeriods) async {
    await LocalDb.putDayResult(
      dayId: '2026-06-15',
      algoVersion: 1, // a pre-rename generation
      payloadJson: jsonEncode({
        'scalars': {'tst_min': 420.0},
        'sleep': {
          'accounting': {
            'confidence': 0.7,
            'value': {'tst_sec': 420 * 60, 'efficiency_pct': 92.0},
          },
          'window': {
            'value': {
              'onset_ms': onset * 1000,
              'offset_ms': wake * 1000,
              'spt_sec': 7 * 3600,
            },
          },
        },
        'sleep_periods': sleepPeriods,
      }),
      windowJson: '{}',
    );
  }

  test(
    'a period stored under the LEGACY keys still renders its times and '
    'duration',
    () async {
      await seed({
        'periods': [
          {
            'is_main': true,
            'start': onset,
            'end': wake,
            'asleep_min': 420,
          },
          {
            'is_main': false,
            'start': napOnset,
            'end': napWake,
            'asleep_min': 38,
          },
        ],
        'total_asleep_min': 458,
      });

      final sleep = await repo.getDaySleep('2026-06-15');
      final periods = (sleep['periods'] as List).cast<Map<String, dynamic>>();

      expect(periods, hasLength(2));

      final main = periods.firstWhere((p) => p['is_main'] == true);
      expect(main['onset_ts'], onset);
      expect(main['wake_ts'], wake);
      expect(
        main['duration_min'],
        420,
        reason: 'the card printed "—" for every pre-rename day',
      );

      final nap = periods.firstWhere((p) => p['is_main'] != true);
      expect(nap['onset_ts'], napOnset);
      expect(nap['wake_ts'], napWake);
      expect(nap['duration_min'], 38);
    },
  );

  test(
    'a period already using the CURRENT keys passes through untouched',
    () async {
      await seed({
        'periods': [
          {
            'is_main': true,
            'onset_ts': onset,
            'wake_ts': wake,
            'duration_min': 415,
            'in_bed_min': 430,
          },
        ],
        'total_asleep_min': 415,
      });

      final sleep = await repo.getDaySleep('2026-06-15');
      final periods = (sleep['periods'] as List).cast<Map<String, dynamic>>();

      expect(periods, hasLength(1));
      expect(periods.first['onset_ts'], onset);
      expect(periods.first['wake_ts'], wake);
      expect(periods.first['duration_min'], 415);
      expect(periods.first['in_bed_min'], 430);
      expect(
        periods.first.containsKey('start'),
        isFalse,
        reason: 'the translation must not invent legacy keys going the other way',
      );
    },
  );

  test(
    'an honestly-null duration is NOT back-filled from a legacy key that is '
    'also absent',
    () async {
      await seed({
        'periods': [
          {
            'is_main': true,
            'onset_ts': onset,
            'wake_ts': wake,
            // staging produced no TST — the screen must keep rendering "—"
            'duration_min': null,
          },
        ],
        'total_asleep_min': null,
      });

      final sleep = await repo.getDaySleep('2026-06-15');
      final periods = (sleep['periods'] as List).cast<Map<String, dynamic>>();

      expect(periods.first['duration_min'], isNull);
      expect(sleep['total_asleep_min'], isNull);
    },
  );
}
