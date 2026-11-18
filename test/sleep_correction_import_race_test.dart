import 'dart:async';
// Real SQLite restore boundaries: the wrapper pauses only the source read.
// Accepted corrections use the actual transactional command, never fake rows.
import 'package:flutter_test/flutter_test.dart';
// sqflite requires its own factory base; delegate every actual storage operation.
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

class SourceReadFactory extends SqfliteDatabaseFactoryBase {
  SourceReadFactory(this.delegate, this.table, this.onRead, {this.onClose});
  final DatabaseFactory delegate;
  final String table;
  final Future<void> Function() onRead;
  final Future<void> Function()? onClose;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final db = await delegate.openDatabase(path, options: options);
    return options?.readOnly == true
        ? SourceReadDatabase(db, table, onRead, onClose: onClose)
        : db;
  }

  @override
  Future<T> invokeMethod<T>(String method, [Object? arguments]) =>
      (delegate as SqfliteDatabaseFactoryMixin).invokeMethod<T>(
        method,
        arguments,
      );
  @override
  Future<String> getDatabasesPath() => delegate.getDatabasesPath();
}

class SourceReadDatabase implements Database {
  SourceReadDatabase(this.delegate, this.table, this.onRead, {this.onClose});
  final Database delegate;
  final String table;
  final Future<void> Function() onRead;
  final Future<void> Function()? onClose;
  bool paused = false;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (!paused &&
        sql.startsWith('SELECT rowid AS _rowid') &&
        sql.contains('FROM $table ')) {
      paused = true;
      await onRead();
    }
    return delegate.rawQuery(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => delegate.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Future<void> close() async {
    await delegate.close();
    await onClose?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected source call: ${invocation.memberName}');
}

const day = '2021-04-06';
Future<void> originalNight() async {
  await LocalDb.putDayResult(
    dayId: day,
    algoVersion: 100,
    payloadJson: '{"scalars":{"readiness":72,"rmssd":44}}',
    windowJson: '{}',
    finalized: true,
    rmssd: 44,
    readiness: 72,
    series: {'readiness': 72, 'rmssd': 44},
  );
  await LocalDb.putSleepOverride(
    dayId: day,
    onsetTs: 1,
    offsetTs: 9000,
    source: 'manual',
  );
  await LocalDb.setFrozenHeadline(day, 72);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-import-race'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final table in ['lift_log', 'day_result']) {
    test('accepted edit during restore survives source page $table', () async {
      await originalNight();
      final backup = await LocalDb.exportCopy();
      final factory = databaseFactory;
      var accepted = false;
      databaseFactory = SourceReadFactory(factory, table, () async {
        await LocalDb.acceptSleepCorrection(
          dayId: day,
          action: 'manual',
          onsetTs: 1800,
          offsetTs: 7200,
        );
        accepted = true;
      });
      Object? failure;
      try {
        await LocalDb.importFromDbFile(backup);
      } catch (e) {
        failure = e;
      } finally {
        databaseFactory = factory;
      }
      expect(accepted, true);
      expect(
        (await LocalDb.getSleepOverride(day))!['onset_ts'],
        1800,
        reason:
            'A restore may not replace the newly accepted window with its older copy',
      );
      expect((await LocalDb.getSleepOverride(day))!['offset_ts'], 7200);
      expect((await LocalDb.sleepCorrection(day))!['generation'], 1);
      expect((await LocalDb.dayResult(day))!['readiness'], isNull);
      expect(await LocalDb.frozenHeadline(), isNull);
      expect(failure, isA<DbImportException>());
      final error = failure as DbImportException;
      if (table == 'lift_log') {
        expect(error.records, 0);
      } else {
        expect(error.records, greaterThan(0));
      }
    });
  }
  test('a pin-only backup cannot revive a corrected night', () async {
    await LocalDb.setFrozenHeadline(day, 72);
    final backup = await LocalDb.exportCopy();
    await LocalDb.wipeAll();
    await originalNight();
    await LocalDb.acceptSleepCorrection(dayId: day, action: 'clear');
    final before = await LocalDb.sleepCorrection(day);
    Object? failure;
    try {
      await LocalDb.importFromDbFile(backup);
    } catch (e) {
      failure = e;
    }
    expect(
      await LocalDb.frozenHeadline(),
      isNull,
      reason:
          'A display-cache-only backup is still an overlap with corrected sleep',
    );
    expect(await LocalDb.sleepCorrection(day), before);
    expect(
      failure,
      isA<DbImportException>().having((e) => e.records, 'committed rows', 0),
    );
  });
  test(
    'an unrelated new correction pauses restore once and preserves a safe retry',
    () async {
      await originalNight();
      final backup = await LocalDb.exportCopy();
      await LocalDb.wipeAll();
      final factory = databaseFactory;
      databaseFactory = SourceReadFactory(
        factory,
        'lift_log',
        () =>
            LocalDb.acceptSleepCorrection(dayId: '2021-04-07', action: 'clear'),
      );
      try {
        await expectLater(
          LocalDb.importFromDbFile(backup),
          throwsA(isA<DbImportException>()),
        );
      } finally {
        databaseFactory = factory;
      }
      final accepted = await LocalDb.sleepCorrection('2021-04-07');
      await LocalDb.importFromDbFile(backup);
      expect(await LocalDb.sleepCorrection('2021-04-07'), accepted);
      expect((await LocalDb.dayResult('2021-04-07'))!['readiness'], isNull);
      expect((await LocalDb.dayResult(day))!['readiness'], 72);
    },
  );
  for (final table in ['lift_log', 'day_result']) {
    test(
      'a reset during restore cannot repopulate cleared data at $table',
      () async {
        await originalNight();
        final backup = await LocalDb.exportCopy();
        final factory = databaseFactory;
        databaseFactory = SourceReadFactory(factory, table, () async {
          await LocalDb.wipeAll();
        });
        Object? failure;
        try {
          await LocalDb.importFromDbFile(backup);
        } catch (e) {
          failure = e;
        } finally {
          databaseFactory = factory;
        }
        expect(
          await LocalDb.dayResult(day),
          isNull,
          reason:
              'An older restore may not recreate data after the accepted reset',
        );
        expect(await LocalDb.getSleepOverride(day), isNull);
        expect(await LocalDb.frozenHeadline(), isNull);
        expect(await LocalDb.metricSeries('readiness'), isEmpty);
        expect(failure, isA<DbImportException>());
      },
    );
  }
  test(
    'reset after the last backup page leaves post-merge cursors empty',
    () async {
      await originalNight();
      final backup = await LocalDb.exportCopy();
      final factory = databaseFactory;
      databaseFactory = SourceReadFactory(
        factory,
        'not_a_table',
        () async {},
        onClose: () async {
          await LocalDb.wipeAll();
        },
      );
      try {
        await expectLater(
          LocalDb.importFromDbFile(backup),
          throwsA(isA<DbImportException>()),
        );
      } finally {
        databaseFactory = factory;
      }
      final db = await LocalDb.instance;
      expect(await db.query('compute_freshness'), isEmpty);
      expect(await LocalDb.dayResult(day), isNull);
      expect(await LocalDb.getSleepOverride(day), isNull);
      expect(await LocalDb.frozenHeadline(), isNull);
      expect(await db.query('body_weight_reading'), isEmpty);
      expect(await db.query('day_zone'), isEmpty);
    },
  );
  test(
    'restore admission remains closed through preference reset completion',
    () async {
      await originalNight();
      final backup = await LocalDb.exportCopy();
      final entered = Completer<void>(), release = Completer<void>();
      final reset = LocalDb.wipeAll(
        afterWipe: () {
          entered.complete();
          return release.future;
        },
      );
      await entered.future;
      try {
        await expectLater(
          LocalDb.importFromDbFile(backup),
          throwsA(
            isA<DbImportException>().having(
              (e) => e.records,
              'committed rows',
              0,
            ),
          ),
        );
        expect(await LocalDb.dayResult(day), isNull);
      } finally {
        release.complete();
        await reset;
      }
      await LocalDb.importFromDbFile(backup);
      expect((await LocalDb.dayResult(day))!['readiness'], 72);
    },
  );

  test(
    'a refused reset releases restore admission without losing existing rows',
    () async {
      await originalNight();
      final backup = await LocalDb.exportCopy();
      final db = await LocalDb.instance;
      await db.execute(
        "CREATE TRIGGER refuse_restore_reset BEFORE DELETE ON day_result BEGIN SELECT RAISE(ABORT, 'authored reset refusal'); END",
      );
      try {
        await expectLater(LocalDb.wipeAll(), throwsA(isA<Exception>()));
        expect((await LocalDb.dayResult(day))!['readiness'], 72);
      } finally {
        await db.execute('DROP TRIGGER refuse_restore_reset');
      }
      await LocalDb.importFromDbFile(backup);
      expect((await LocalDb.dayResult(day))!['readiness'], 72);
    },
  );
}
