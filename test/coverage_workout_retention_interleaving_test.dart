// Real SQLite results;only the driver's scheduling boundary is controlled.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'sleep_correction_import_race_test.dart'
    show SourceReadFactory, SourceReadDatabase;
import 'support/coverage_store.dart';

class _RetentionFactory extends SourceReadFactory {
  _RetentionFactory(DatabaseFactory base, this.cutoff)
    : super(base, 'unused', () async {});
  final int cutoff;
  bool armed = true;
  int boundaries = 0;
  int? pruned;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    return _RetentionDatabase(
      await delegate.openDatabase(path, options: options),
      this,
    );
  }
}

class _RetentionDatabase extends SourceReadDatabase {
  _RetentionDatabase(Database db, this.owner)
    : super(db, 'unused', () async {});
  final _RetentionFactory owner;
  @override
  bool get isOpen => delegate.isOpen;
  @override
  String get path => delegate.path;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => delegate.transaction(action, exclusive: exclusive);
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final rows = await delegate.rawQuery(sql, arguments);
    if (owner.armed &&
        sql.startsWith('SELECT s.id AS id, COUNT(d.rec_ts) AS n')) {
      owner.armed = false;
      owner.boundaries++;
      // The actual public retention transaction runs after a real aggregate
      // snapshot and before the next independently awaited sample read.
      owner.pruned = await LocalDb.pruneDecodedBeforeRecTs(owner.cutoff);
    }
    return rows;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('workout-retention-interleaving'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final storedMax in <int?>[null, 145]) {
    for (final refuse in [false, true]) {
      test(
        'COV-67 workout list retention refusal=$refuse storedMax=$storedMax preserves durable history and retries',
        () async {
          final start =
              DateTime.now()
                  .subtract(const Duration(days: 20))
                  .millisecondsSinceEpoch ~/
              1000;
          final date = dayLabelOf(
            DateTime.fromMillisecondsSinceEpoch(start * 1000),
          );
          await LocalDb.putDayResult(
            dayId: date,
            algoVersion: 101,
            payloadJson: '{"authored":"retained finalized output"}',
            windowJson: '{}',
            finalized: true,
          );
          await LocalDb.putSession({
            'id': 'authored-retention-workout',
            'start_ts': start,
            'end_ts': start + 180,
            'type': 'weight_training',
            'status': 'done',
            'source': 'manual',
            'created_at': 1,
            'duration_min': 3,
            'calories': 120,
            'avg_hr': 88,
            'max_hr': storedMax,
            'zone_min_json': '[1,2]',
          });
          final times = [start + 30, start + 60, start + 90];
          final rates = [90, 120, 150];
          await LocalDb.commitSyncBatch(
            [
              for (var i = 0; i < times.length; i++)
                RawRecord(
                  counter: i,
                  packetType: 47,
                  hex: '00',
                  capturedAt: times[i] * 1000,
                  recTs: times[i],
                ),
            ],
            [
              for (var i = 0; i < times.length; i++)
                Sample(
                  tsEpoch: times[i],
                  counter: i,
                  hr: rates[i],
                  rrIntervalsMs: [60000 ~/ rates[i]],
                  ax: 0,
                  ay: 0,
                  az: 0,
                ),
            ],
            deviceFamily: 'gen4',
          );
          final original = await LocalDb.instance;
          final sessions = await original.query('sessions');
          final results = await original.query('day_result');
          final decoded = await original.query('decoded_onehz');
          final beats = await original.query('decoded_rr');
          if (refuse) {
            await original.execute(
              "CREATE TRIGGER authored_retention_refusal BEFORE DELETE ON decoded_onehz BEGIN SELECT RAISE(ABORT,'authored retention refusal'); END",
            );
          }
          final factory = databaseFactory;
          await LocalDb.close();
          final held = _RetentionFactory(factory, start + 181);
          databaseFactory = held;
          try {
            final db = await LocalDb.instance;
            final repo = LocalRepositoryImpl(getProfileMap: () => {'age': 30});
            final list = await repo.getWorkouts(range: 'all');
            final row = (list['workouts'] as List).single as Map;
            expect(held.boundaries, 1);
            expect(row['avg_hr'], refuse ? 88 : 120);
            expect(row['max_hr'], refuse ? storedMax : (storedMax ?? 150));
            expect(row['min_hr'], refuse ? null : 90);
            expect(list['summary'], {
              'count': 1,
              'total_min': 3,
              'total_calories': 120,
              'zone_min': [1, 2],
            });
            expect(await db.query('sessions'), sessions);
            expect(await db.query('day_result'), results);
            if (refuse) {
              expect(held.pruned, isNull);
              expect(await db.query('decoded_onehz'), decoded);
              expect(
                await db.query('decoded_rr'),
                beats,
                reason:
                    'The earlier beat delete rolls back with the refused parent delete',
              );
              await (db as _RetentionDatabase).delegate.execute(
                'DROP TRIGGER authored_retention_refusal',
              );
              held.armed = true;
              final retried = await repo.getWorkouts(range: 'all');
              final replacement = (retried['workouts'] as List).single as Map;
              expect(replacement['avg_hr'], 120);
              expect(replacement['min_hr'], 90);
              expect(replacement['max_hr'], storedMax ?? 150);
              expect(held.boundaries, 2);
            }
            expect(held.pruned, greaterThanOrEqualTo(3));
            expect(await db.query('decoded_onehz'), isEmpty);
            expect(await db.query('decoded_rr'), isEmpty);
            expect(await db.query('sessions'), sessions);
            expect(await db.query('day_result'), results);
          } finally {
            await LocalDb.close();
            databaseFactory = factory;
            final db = await LocalDb.instance;
            await db.execute(
              'DROP TRIGGER IF EXISTS authored_retention_refusal',
            );
          }
        },
      );
    }
  }
}
