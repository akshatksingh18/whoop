// Shared score/trace/split transaction over actual SQLite refusals and ownership.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:whoop_companion/data/db.dart';
import '../support/coverage_store.dart';
import '../support/store_fixtures.dart';

const _id = 'authored-atomic-session', _other = 'authored-other-session';
const _start = 1760004000, _end = _start + 240;
const _old = <Map<String, Object?>>[
  {
    'km': 1,
    'meters': 800.0,
    'duration_sec': 240,
    'avg_hr': 130.0,
    'net_elev_m': null,
  },
];
const _new = <Map<String, Object?>>[
  {
    'km': 1,
    'meters': 1000.0,
    'duration_sec': 220,
    'avg_hr': 140.0,
    'net_elev_m': 0.0,
  },
  {
    'km': 2,
    'meters': 100.0,
    'duration_sec': 20,
    'avg_hr': null,
    'net_elev_m': null,
  },
];

Future<int> _write({
  List<Map<String, Object?>>? splits = _new,
  bool guarded = true,
}) => LocalDb.setSessionScores(
  _id,
  strain: 8,
  calories: 200,
  caloriesBasis: 'active',
  maxHr: 150,
  zoneMinJson: '[0,1,2,0,0,0]',
  avgHr: 140,
  traceJson: '{"fresh":true}',
  traceSamples: 240,
  stagedSplits: splits,
  expectedWindow: guarded
      ? (startTs: _start, endTs: _end, status: 'done')
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('session-split-atomic-store'));
  setUp(() async {
    await resetCoverageStore();
    for (final id in [_id, _other]) {
      await LocalDb.putSession({
        'id': id,
        'start_ts': _start,
        'end_ts': _end,
        'status': 'done',
        'type': 'cycling',
        'source': 'band',
        'created_at': 1,
        'strain': 3.0,
        'calories': 100.0,
        'avg_hr': 130,
        'hrr_bpm': 17.0,
        'trace_json': '{"old":true}',
        'trace_samples': 12,
      });
      await LocalDb.putWorkoutSplits(id, _old);
    }
    await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
  });
  tearDown(() async {
    final db = await LocalDb.instance;
    await db.execute('DROP TRIGGER IF EXISTS authored_split_refusal');
    await db.execute('DROP TRIGGER IF EXISTS authored_session_refusal');
  });
  tearDownAll(LocalDb.close);

  Future<void> unchangedOther(
    Map<String, Object?>? owner,
    List<Map<String, Object?>> splits,
  ) async {
    expect(await LocalDb.session(_other), owner);
    expect(await splitRows(_other), splits);
    final metrics = await (await LocalDb.instance).query('metric_series');
    expect(metrics, hasLength(1));
    expect(metrics.single['value'], 1234);
  }

  for (final prior in [false, true]) {
    for (final refusedKm in [1, 2]) {
      test(
        'refused split $refusedKm with prior=$prior rolls back trace and every child;retry is idempotent',
        () async {
          final db = await LocalDb.instance;
          if (!prior) await LocalDb.putWorkoutSplits(_id, []);
          final before = await LocalDb.session(_id);
          final splits = await splitRows(_id);
          final other = await LocalDb.session(_other);
          final otherSplits = await splitRows(_other);
          await db.execute(
            "CREATE TRIGGER authored_split_refusal BEFORE INSERT ON workout_split WHEN NEW.session_id = '$_id' AND NEW.km = $refusedKm BEGIN SELECT RAISE(ABORT, 'authored split refusal'); END",
          );
          await expectLater(_write(), throwsA(isA<DatabaseException>()));
          expect(await LocalDb.session(_id), before);
          expect(await splitRows(_id), splits);
          await unchangedOther(other, otherSplits);
          await db.execute('DROP TRIGGER authored_split_refusal');
          expect(await _write(), 1);
          final saved = (await LocalDb.session(_id))!;
          expect(saved['trace_json'], '{"fresh":true}');
          expect(saved['trace_samples'], 240);
          expect(saved['avg_hr'], 140);
          expect(saved['hrr_bpm'], 17.0);
          expect(saved['type'], 'cycling');
          final frozen = await splitRows(_id);
          expect(frozen, [
            for (final r in _new) {'session_id': _id, ...r},
          ]);
          expect(await _write(), 1);
          expect(await LocalDb.session(_id), saved);
          expect(await splitRows(_id), frozen);
          await unchangedOther(other, otherSplits);
        },
      );
    }
  }
  test('refused session update cannot replace any existing splits', () async {
    final db = await LocalDb.instance;
    final before = await db.query('sessions');
    final splits = await db.query('workout_split');
    await db.execute(
      "CREATE TRIGGER authored_session_refusal BEFORE UPDATE ON sessions WHEN OLD.id = '$_id' BEGIN SELECT RAISE(ABORT, 'authored session refusal'); END",
    );
    await expectLater(_write(), throwsA(isA<DatabaseException>()));
    expect(await db.query('sessions'), before);
    expect(await db.query('workout_split'), splits);
    await db.execute('DROP TRIGGER authored_session_refusal');
    expect(await _write(), 1);
    expect((await LocalDb.session(_id))!['trace_samples'], 240);
  });
  for (final changed in ['start', 'end', 'status', 'deleted']) {
    test(
      'the $changed owner rejects old-window trace and child publication',
      () async {
        final db = await LocalDb.instance;
        if (changed == 'deleted') {
          await LocalDb.deleteSession(_id);
        } else {
          await db.update(
            'sessions',
            {
              if (changed == 'start') 'start_ts': _start + 1,
              if (changed == 'end') 'end_ts': _end + 1,
              if (changed == 'status') 'status': 'live',
            },
            where: 'id = ?',
            whereArgs: [_id],
          );
        }
        final sessions = await db.query('sessions');
        final splits = await db.query('workout_split');
        expect(await _write(), 0);
        expect(await db.query('sessions'), sessions);
        expect(await db.query('workout_split'), splits);
      },
    );
  }
  test(
    'omitted staged rows retain splits and banked null-protected values',
    () async {
      final before = await splitRows(_id);
      expect(
        await LocalDb.setSessionScores(
          _id,
          strain: 8,
          calories: 200,
          maxHr: 150,
          zoneMinJson: '[]',
        ),
        1,
      );
      final row = (await LocalDb.session(_id))!;
      expect(row['avg_hr'], 130);
      expect(row['trace_json'], '{"old":true}');
      expect(row['trace_samples'], 12);
      expect(row['hrr_bpm'], 17.0);
      expect(await splitRows(_id), before);
    },
  );
  test(
    'an explicit empty replacement clears only the matching owner',
    () async {
      final other = await LocalDb.session(_other);
      final otherSplits = await splitRows(_other);
      expect(await _write(splits: []), 1);
      expect(await splitRows(_id), isEmpty);
      expect((await LocalDb.session(_id))!['trace_samples'], 240);
      await unchangedOther(other, otherSplits);
    },
  );
}
