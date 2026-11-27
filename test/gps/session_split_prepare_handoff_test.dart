// Actual re-score/input storage,with SQLite read/write faults and real owner edits.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/gps/route_models.dart';
import '../compute/prepare_handoff_test.dart' show raw;
import '../support/coverage_store.dart';
import '../support/store_fixtures.dart';

const _id = 'authored-split-prepare', _ts = 1760004000;
Future<void> _seed() async {
  final raws = <RawRecord>[], samples = <Sample?>[];
  for (var i = 0; i < 240; i++) {
    final bytes = p.hexToBytes(raw(_ts + i, 140));
    ByteData.sublistView(bytes).setUint32(3, i + 1, Endian.little);
    final decoded = p.parseR24(bytes)!;
    raws.add(
      RawRecord(
        counter: decoded.counter,
        packetType: 47,
        hex: bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        capturedAt: (_ts + i) * 1000,
        recTs: _ts + i,
      ),
    );
    samples.add(
      Sample(
        tsEpoch: decoded.tsEpoch,
        counter: decoded.counter,
        hr: decoded.hr,
        ax: decoded.accelG[0],
        ay: decoded.accelG[1],
        az: decoded.accelG[2],
      ),
    );
  }
  await LocalDb.commitSyncBatch(raws, samples, deviceFamily: 'gen4');
  await LocalDb.putSession({
    'id': _id,
    'start_ts': _ts,
    'end_ts': _ts + 240,
    'type': 'cycling',
    'status': 'done',
    'source': 'band',
    'device_family': 'gen4',
    'trace_samples': 0,
    'created_at': 1,
  });
  await LocalDb.appendRoutePoints(_id, [
    for (var i = 0; i <= 240; i++)
      RoutePoint(
        seq: i,
        tsMs: (_ts + i) * 1000,
        lat: 0,
        lng: i * .00004,
        accuracy: 3,
        speed: 4.4,
        alt: null,
      ).toRow(_id),
  ]);
  await LocalDb.putWorkoutSplits(_id, [
    {
      'km': 1,
      'meters': 800.0,
      'duration_sec': 240,
      'avg_hr': 130.0,
      'net_elev_m': null,
    },
  ]);
}

LocalRepositoryImpl _repo({void Function()? changed}) => LocalRepositoryImpl(
  getProfileMap: () => {
    'age': 30,
    'sex': 'f',
    'weight_kg': 70.0,
    'height_cm': 170.0,
    'resting_hr': 60,
  },
  onSessionChanged: changed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void Function()? onStageRead;
  setUpAll(() async {
    await coverageStore('session-split-prepare');
    // Observe the completed real read;the test's concurrent edit queues on
    // the same SQLite connection before the later score/split transaction.
    // ignore: experimental_member_use
    databaseFactory = SqfliteDatabaseFactoryLogger(
      databaseFactoryFfiNoIsolate,
      options: SqfliteLoggerOptions(
        log: (event) {
          if (event is SqfliteLoggerSqlEvent &&
              event.sql.startsWith('SELECT * FROM workout_route ') &&
              onStageRead != null) {
            final action = onStageRead!;
            onStageRead = null;
            action();
          }
        },
      ),
    );
  });
  setUp(() async {
    await resetCoverageStore();
    await _seed();
  });
  tearDown(() async {
    onStageRead = null;
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_score_refusal',
    );
  });
  tearDownAll(LocalDb.close);

  for (final mode in [
    'read-refusal',
    'malformed-route',
    'absent-route',
    'single-fix',
    'stationary-route',
    'score-refusal',
  ]) {
    test(
      'split preparation $mode preserves absence/input and retry eligibility',
      () async {
        final db = await LocalDb.instance;
        if (mode == 'absent-route') {
          await db.delete(
            'workout_route',
            where: 'session_id = ?',
            whereArgs: [_id],
          );
        } else if (mode == 'single-fix') {
          await db.delete(
            'workout_route',
            where: 'session_id = ? AND seq > 0',
            whereArgs: [_id],
          );
        } else if (mode == 'stationary-route') {
          await db.update(
            'workout_route',
            {'lng': 0.0},
            where: 'session_id = ?',
            whereArgs: [_id],
          );
        } else if (mode == 'malformed-route') {
          await db.update(
            'workout_route',
            {'lat': 'authored-unreadable'},
            where: 'session_id = ? AND seq = 1',
            whereArgs: [_id],
          );
        } else if (mode == 'score-refusal') {
          await db.execute(
            "CREATE TRIGGER authored_score_refusal BEFORE UPDATE ON sessions WHEN OLD.id = '$_id' BEGIN SELECT RAISE(ABORT, 'authored score refusal'); END",
          );
        }
        final frames = await db.query('decoded_onehz');
        final route = await LocalDb.routePoints(_id);
        final before = await LocalDb.session(_id);
        final splits = await splitRows(_id);
        final failed = [
          'read-refusal',
          'malformed-route',
          'score-refusal',
        ].contains(mode);
        final repo = _repo();
        if (mode == 'read-refusal') {
          await db.execute(
            'ALTER TABLE workout_route RENAME TO authored_unavailable_route',
          );
        }
        try {
          await repo.getWorkout(_id);
          final row = (await LocalDb.session(_id))!;
          expect(row['trace_samples'], failed ? 0 : 240);
          if (failed) expect(row['trace_json'], before!['trace_json']);
          expect(await splitRows(_id), splits);
          expect(await db.query('decoded_onehz'), frames);
          if (mode == 'read-refusal') {
            expect(
              await db.query('authored_unavailable_route', orderBy: 'seq'),
              route,
            );
          } else {
            expect(await LocalDb.routePoints(_id), route);
          }
        } finally {
          if (mode == 'read-refusal') {
            await db.execute(
              'ALTER TABLE authored_unavailable_route RENAME TO workout_route',
            );
          }
        }
        if (failed) {
          if (mode == 'malformed-route') {
            await db.update(
              'workout_route',
              {'lat': 0.0},
              where: 'session_id = ? AND seq = 1',
              whereArgs: [_id],
            );
          }
          if (mode == 'score-refusal') {
            await db.execute('DROP TRIGGER authored_score_refusal');
          }
          await repo.getWorkout(_id);
          expect((await LocalDb.session(_id))!['trace_samples'], 240);
          final frozen = await splitRows(_id);
          expect(frozen, hasLength(2));
          expect(frozen.first['net_elev_m'], isNull);
          await repo.getWorkout(_id);
          expect(await splitRows(_id), frozen);
        }
        expect(await db.query('decoded_onehz'), frames);
        expect(await db.query('day_result'), isEmpty);
      },
    );
  }

  for (final mode in ['start', 'end', 'status', 'delete']) {
    test(
      'actual $mode edit during route preparation cannot publish old-window trace/splits',
      () async {
        final db = await LocalDb.instance;
        final frames = await db.query('decoded_onehz');
        final splits = await splitRows(_id);
        Future<void>? mutation;
        var edits = 0, publications = 0;
        onStageRead = () {
          edits++;
          mutation = () async {
            if (mode == 'delete') {
              await LocalDb.deleteSession(_id);
            } else {
              await db.update(
                'sessions',
                {
                  if (mode == 'start') 'start_ts': _ts + 1,
                  if (mode == 'end') 'end_ts': _ts + 239,
                  if (mode == 'status') 'status': 'live',
                },
                where: 'id = ?',
                whereArgs: [_id],
              );
            }
          }();
        };
        await _repo(changed: () => publications++).getWorkout(_id);
        await mutation;
        expect(edits, 1);
        expect(publications, 0);
        final row = await LocalDb.session(_id);
        if (mode == 'delete') {
          expect(row, isNull);
          expect(await splitRows(_id), isEmpty);
          expect(await LocalDb.routePoints(_id), isEmpty);
        } else {
          expect(row!['trace_samples'], 0);
          expect(row['trace_json'], isNull);
          expect(await splitRows(_id), splits);
          if (mode == 'start') expect(row['start_ts'], _ts + 1);
          if (mode == 'end') expect(row['end_ts'], _ts + 239);
          if (mode == 'status') expect(row['status'], 'live');
        }
        expect(await db.query('decoded_onehz'), frames);
        expect(await db.query('day_result'), isEmpty);
      },
    );
  }
}
