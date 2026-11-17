// Real day-export SQLite handles, including failures after destination open.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
// The installed factory base is required to observe native handle lifetime.
// All allowed database operations still execute against real FFI SQLite.
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

class _ExportHandles extends SqfliteDatabaseFactoryBase {
  final live = <int, String>{};
  int? sourceId;
  bool refuseCopy = false;
  @override
  Future<T> invokeMethod<T>(String method, [Object? arguments]) async {
    final args = arguments is Map ? arguments : const {};
    if (refuseCopy && method == 'batch' && args['id'] != sourceId) {
      final operations = args['operations'];
      if (operations is List &&
          operations.any(
            (op) =>
                op is Map &&
                '${op['sql']}'.contains('INSERT') &&
                '${op['sql']}'.contains('metric_series'),
          )) {
        throw StateError('authored destination write refusal');
      }
    }
    final result =
        await (databaseFactoryFfiNoIsolate as SqfliteDatabaseFactoryMixin)
            .invokeMethod<dynamic>(method, arguments);
    if (method == 'openDatabase') {
      final id = (result as Map)['id'] as int;
      live[id] = args['path'] as String;
    } else if (method == 'closeDatabase') {
      live.remove(args['id']);
    }
    return result as T;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ExportHandles boundary;
  late AppState app;
  setUpAll(() async {
    await coverageStore('selected-export-lifetime', fresh: true);
    databaseFactory = boundary = _ExportHandles();
  });
  setUp(() async {
    boundary.refuseCopy = false;
    await resetCoverageStore();
    expect(boundary.live, hasLength(1));
    boundary.sourceId = boundary.live.keys.single;
    app = AppState.forTesting();
    for (final day in ['2021-04-06', '2021-04-07']) {
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'date': day,
          'scalars': {'steps': 1200.0},
        }),
        windowJson: '{}',
        finalized: false,
        series: {'steps': 1200},
      );
    }
  });
  tearDown(() async {
    app.dispose();
    boundary.refuseCopy = false;
    // Preserve each authored partial export; close any handle left by the
    // original failing implementation without deleting its recovery bytes.
    for (final path in [
      for (final e in boundary.live.entries)
        if (e.key != boundary.sourceId) e.value,
    ]) {
      await (await databaseFactory.openDatabase(path)).close();
    }
  });
  tearDownAll(LocalDb.close);
  for (final throughApp in [false, true]) {
    for (final failure in [
      'invalid selection',
      'source read',
      'destination write',
    ]) {
      test(
        'COV-62 selected export $failure through AppState=$throughApp closes its destination',
        () async {
          final db = await LocalDb.instance;
          final rows = await db.query('day_result', orderBy: 'day_id');
          final series = await db.query('metric_series', orderBy: 'date,key');
          final originalHandles = Set<int>.of(boundary.live.keys);
          if (failure == 'source read') {
            await db.execute(
              'ALTER TABLE metric_series RENAME TO authored_hidden_series',
            );
          }
          boundary.refuseCopy = failure == 'destination write';
          try {
            final selection = {
              failure == 'invalid selection'
                  ? 'not-a-calendar-day'
                  : '2021-04-06',
            };
            final exported = throughApp
                ? app.exportDaysDb(selection)
                : LocalDb.exportDaysDb(selection);
            await expectLater(
              exported,
              throwsA(
                failure == 'invalid selection'
                    ? isA<ArgumentError>()
                    : failure == 'source read'
                    ? isA<DatabaseException>()
                    : isA<StateError>(),
              ),
            );
            expect(
              boundary.live.keys.toSet(),
              originalHandles,
              reason:
                  'A failed export must close the output, leaving the source open',
            );
          } finally {
            boundary.refuseCopy = false;
            if (failure == 'source read') {
              await db.execute(
                'ALTER TABLE authored_hidden_series RENAME TO metric_series',
              );
            }
          }
          expect(await db.query('day_result', orderBy: 'day_id'), rows);
          expect(await db.query('metric_series', orderBy: 'date,key'), series);
          expect(
            (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
            'ok',
          );
        },
      );
    }
    test(
      'COV-62 selected export success through AppState=$throughApp closes and retains only its selected day',
      () async {
        final db = await LocalDb.instance;
        final rows = await db.query('day_result', orderBy: 'day_id');
        final handles = Set<int>.of(boundary.live.keys);
        final path = throughApp
            ? await app.exportDaysDb({'2021-04-06'})
            : await LocalDb.exportDaysDb({'2021-04-06'});
        expect(boundary.live.keys.toSet(), handles);
        final exported = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          expect((await exported.query('day_result')).map((r) => r['day_id']), [
            '2021-04-06',
          ]);
          expect(
            (await exported.query('metric_series')).map((r) => r['date']),
            ['2021-04-06'],
          );
          expect(
            (await exported.rawQuery(
              'PRAGMA integrity_check',
            )).single.values.single,
            'ok',
          );
        } finally {
          await exported.close();
        }
        expect(await db.query('day_result', orderBy: 'day_id'), rows);
        expect(boundary.live.keys.toSet(), handles);
      },
    );
  }
}
