// Real recent-session sweeps across late substrate and user activity edits.
// All measurements, profiles and session identifiers here are synthetic.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/manual_session.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late LocalRepositoryImpl repo;
  late int start;
  var changes = 0;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final dir = (await Directory(
      'build/coverage-remainder/session-sweep',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${dir.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    changes = 0;
    start = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7200;
    repo = LocalRepositoryImpl(
      getProfileMap: () => {
        'age': 30,
        'weight_kg': 75,
        'height_cm': 180,
        'sex': 'm',
        'resting_hr': 55,
      },
      onSessionChanged: () => changes++,
    );
  });
  tearDownAll(LocalDb.close);
  Future<void> seed(int lo, int hi, int hr) async {
    await LocalDb.commitSyncBatch(
      [
        for (var at = lo; at < hi; at++)
          RawRecord(
            counter: at,
            packetType: 47,
            hex: 'synthetic',
            capturedAt: at * 1000,
            recTs: at,
          ),
      ],
      [
        for (var at = lo; at < hi; at++)
          Sample(
            tsEpoch: at,
            counter: at,
            hr: hr,
            rrIntervalsMs: const [],
            ax: 0,
            ay: 0,
            az: 0,
          ),
      ],
      deviceFamily: 'gen4',
    );
  }

  Future<void> row({
    String status = 'done',
    String type = 'weight_training',
    int? end,
    bool fabricated = false,
  }) => LocalDb.putSession({
    'id': 'synthetic-session',
    'start_ts': start,
    'end_ts': end ?? start + 180,
    'type': type,
    'status': status,
    'source': 'manual',
    'created_at': 1,
    'end_ts_fabricated': fabricated ? 1 : 0,
  });

  test(
    'a settled session reprices a user-corrected strength activity',
    () async {
      await row();
      await seed(start, start + 180, 145);
      await LocalDb.setCursor('rec_ts_hw', '${start + 180}');
      expect(await repo.rescoreRecentSessions(), 1);
      expect(
        (await LocalDb.session('synthetic-session'))!['calories'],
        closeTo(2.5 * 75 * 3 / 60, .0001),
      );
      changes = 0;
      // This is the narrow writer used by ActivitySummary's Change activity.
      await LocalDb.setSessionType('synthetic-session', 'bodyweight');
      expect(await repo.rescoreRecentSessions(), 1);
      final saved = (await LocalDb.session('synthetic-session'))!;
      expect(saved['calories'], closeTo(2 * 75 * 3 / 60, .0001));
      expect(saved['calories_basis'], kCaloriesBasisActive);
      expect(changes, 1);
    },
  );

  test(
    'an unchanged settled session does not publish redundant writes',
    () async {
      await row();
      await seed(start, start + 180, 145);
      await LocalDb.setCursor('rec_ts_hw', '${start + 180}');
      expect(await repo.rescoreRecentSessions(), 1);
      changes = 0;
      expect(await repo.rescoreRecentSessions(), 0);
      expect(changes, 0);
    },
  );

  test(
    'late records behind an unfinished frontier improve the saved trace',
    () async {
      await row();
      await seed(start, start + 60, 110);
      expect(await repo.rescoreRecentSessions(), 1);
      expect(
        (await LocalDb.session('synthetic-session'))!['trace_samples'],
        60,
      );
      await seed(start + 60, start + 180, 170);
      expect(await repo.rescoreRecentSessions(), 1);
      final saved = (await LocalDb.session('synthetic-session'))!;
      expect(saved['trace_samples'], 180);
      expect(saved['avg_hr'], 150);
    },
  );

  test(
    'a start-only retime cannot inherit the earlier window cache entry',
    () async {
      await row();
      await seed(start, start + 180, 110);
      await LocalDb.setCursor('rec_ts_hw', '${start + 180}');
      await repo.rescoreRecentSessions();
      final earlier = start - 60;
      await repo.setWorkoutWindow(
        'synthetic-session',
        startTs: earlier,
        endTs: start + 180,
      );
      // A later import supplies the previously absent beginning of the new window.
      await seed(earlier, start, 170);
      expect(await repo.rescoreRecentSessions(), 1);
      final saved = (await LocalDb.session('synthetic-session'))!;
      expect(saved['start_ts'], earlier);
      expect(saved['end_ts'], start + 180);
      expect(saved['trace_samples'], 240);
      expect(saved['avg_hr'], 125);
    },
  );

  test('a live session becomes scoreable after its finish commits', () async {
    await row(status: 'live');
    await seed(start, start + 180, 145);
    await LocalDb.setCursor('rec_ts_hw', '${start + 180}');
    expect(await repo.rescoreRecentSessions(), 0);
    expect(
      (await LocalDb.session('synthetic-session'))!['trace_samples'],
      isNull,
    );
    await db.update(
      'sessions',
      {'status': 'done'},
      where: 'id = ?',
      whereArgs: ['synthetic-session'],
    );
    expect(await repo.rescoreRecentSessions(), 1);
    expect((await LocalDb.session('synthetic-session'))!['trace_samples'], 180);
  });

  test('a fabricated end cannot acquire a physiological score', () async {
    await row(fabricated: true);
    await seed(start, start + 180, 145);
    expect(await repo.rescoreRecentSessions(), 0);
    final saved = (await LocalDb.session('synthetic-session'))!;
    expect(saved['strain'], isNull);
    expect(saved['calories'], isNull);
    expect(saved['trace_samples'], isNull);
    expect(changes, 0);
  });

  test(
    'a read failure remains retryable instead of settling an empty trace',
    () async {
      await row();
      await seed(start, start + 180, 145);
      await LocalDb.setCursor('rec_ts_hw', '${start + 180}');
      await db.execute(
        'ALTER TABLE decoded_onehz RENAME TO synthetic_hidden_hr',
      );
      try {
        expect(await repo.rescoreRecentSessions(), 0);
        expect((await LocalDb.session('synthetic-session'))!['strain'], isNull);
      } finally {
        await db.execute(
          'ALTER TABLE synthetic_hidden_hr RENAME TO decoded_onehz',
        );
      }
      expect(await repo.rescoreRecentSessions(), 1);
      expect(
        (await LocalDb.session('synthetic-session'))!['trace_samples'],
        180,
      );
    },
  );

  test(
    'privacy, effort and independently saved HR recovery survive scoring',
    () async {
      await row();
      await db.update(
        'sessions',
        {'private': 1, 'rpe': 8.5, 'hrr_bpm': 24},
        where: 'id = ?',
        whereArgs: ['synthetic-session'],
      );
      await seed(start, start + 180, 145);
      await repo.rescoreRecentSessions();
      final saved = (await LocalDb.session('synthetic-session'))!;
      expect(saved['private'], 1);
      expect(saved['rpe'], 8.5);
      expect(saved['hrr_bpm'], 24);
    },
  );

  test('a closed session with no retained recordings stays unscored', () async {
    await row();
    expect(await repo.rescoreRecentSessions(), 0);
    final saved = (await LocalDb.session('synthetic-session'))!;
    expect(saved['calories'], isNull);
    expect(saved['strain'], isNull);
    expect(changes, 0);
  });
}
