// Refuse only native SQL-control messages; every row/cursor uses real SQLite.
import 'package:flutter_test/flutter_test.dart';
// sqflite exposes no public fault-injection wrapper. Delegate all other methods
// to the installed FFI factory, as the existing rebuild-boundary controls do.
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'support/coverage_store.dart';

class _DurabilityBoundary extends SqfliteDatabaseFactoryBase {
  String? fault;
  final controls = <String>[];
  @override
  Future<T> invokeMethod<T>(String method, [Object? arguments]) async {
    final sql = arguments is Map ? arguments['sql'] : null;
    if (fault != null &&
        sql is String &&
        sql.startsWith('PRAGMA synchronous')) {
      controls.add(sql);
      if (sql == 'PRAGMA synchronous=FULL') {
        if (fault == 'ignored FULL') return null as T;
        if (fault == 'refused FULL') throw StateError('authored FULL refusal');
      }
      if (sql == 'PRAGMA synchronous' && fault == 'refused readback') {
        throw StateError('authored readback refusal');
      }
      if (sql == 'PRAGMA synchronous=NORMAL' && fault == 'refused restore') {
        throw StateError('authored NORMAL refusal');
      }
    }
    return (databaseFactoryFfiNoIsolate as SqfliteDatabaseFactoryMixin)
        .invokeMethod<T>(method, arguments);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _DurabilityBoundary boundary;
  setUpAll(() async {
    await coverageStore('sync-durability-fallback');
    boundary = _DurabilityBoundary();
    databaseFactory = boundary;
  });
  setUp(() async {
    boundary.fault = null;
    boundary.controls.clear();
    await resetCoverageStore();
  });
  tearDown(() async {
    boundary.fault = null;
    await (await LocalDb.instance).execute('PRAGMA synchronous=NORMAL');
  });
  tearDownAll(LocalDb.close);
  const ts = 1620000000;
  final raw = RawRecord(
    counter: 17,
    packetType: 0x2f,
    hex: '2f110000',
    capturedAt: ts * 1000,
    recTs: ts,
  );
  const token = 'a1b2c3d4';
  for (final mode in [
    'ignored FULL',
    'refused FULL',
    'refused readback',
    'refused restore',
  ]) {
    for (final refusedRow in [false, true]) {
      test(
        'COV-61 $mode retains atomic sync outcome with row refusal=$refusedRow',
        () async {
          final db = await LocalDb.instance;
          final log = <String>[];
          if (refusedRow) {
            await db.execute(
              "CREATE TEMP TRIGGER refuse_authored_sync BEFORE INSERT ON samples "
              "BEGIN SELECT RAISE(ABORT,'authored sync row refusal'); END",
            );
          }
          boundary.fault = mode;
          Future<void> commit() => LocalDb.commitSyncBatch(
            [raw],
            [Sample(tsEpoch: ts, counter: 17, hr: 63)],
            trimToken: token,
            extraCursors: {'authored-extra': 'kept'},
            onCheckpoint: log.add,
          );
          if (refusedRow) {
            await expectLater(commit(), throwsA(isA<DatabaseException>()));
          } else {
            await commit();
          }
          expect(boundary.controls.first, 'PRAGMA synchronous=FULL');
          expect(boundary.controls.last, 'PRAGMA synchronous=NORMAL');
          expect(
            log.where((s) => s.contains('downgrades_total=')),
            mode == 'refused restore' ? isEmpty : hasLength(1),
          );
          boundary.fault = null;
          expect(await db.query('samples'), hasLength(refusedRow ? 0 : 1));
          expect(
            await LocalDb.getCursor('strap_trim'),
            refusedRow ? null : token,
          );
          expect(
            await LocalDb.getCursorInt('counter_hw'),
            refusedRow ? null : 17,
          );
          expect(
            await LocalDb.getCursorInt('rec_ts_hw'),
            refusedRow ? null : ts,
          );
          expect(
            await LocalDb.getCursor('authored-extra'),
            refusedRow ? null : 'kept',
          );
          final level = (await db.rawQuery(
            'PRAGMA synchronous',
          )).single.values.single;
          expect(
            level,
            mode == 'ignored FULL' || mode == 'refused FULL'
                ? 1
                : mode == 'refused restore'
                ? 2
                : 1,
          );
          // A refused restore may leave FULL in place; explicitly restore the
          // fixture before retrying. Do not call that path a physical fsync test.
          await db.execute('PRAGMA synchronous=NORMAL');
          if (refusedRow) await db.execute('DROP TRIGGER refuse_authored_sync');
          log.clear();
          await commit();
          expect(await db.query('samples'), hasLength(1));
          expect(await LocalDb.getCursor('strap_trim'), token);
          expect(log.any((s) => s.contains('downgrades_total=')), false);
          expect(
            (await db.rawQuery('PRAGMA synchronous')).single.values.single,
            1,
          );
        },
      );
    }
  }
}
