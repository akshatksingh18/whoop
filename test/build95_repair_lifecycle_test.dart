// Build 95 lifecycle regressions; all values and files are synthetic.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/auto_backup.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/media_backup.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/progress_review.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/import/backup_crypto.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'audit_build95_extended_synthetic.db';
    await databaseFactory.deleteDatabase(
      p.join(await getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('b95_extended_synthetic_');
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
  });
  tearDown(() async {
    WorkoutClock.current = null;
    LiveDraft.clear();
    DayClock.install([], []);
    await FileLog.write('Synthetic test cleanup barrier');
    await tmp.delete(recursive: true);
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await getDatabasesPath(), LocalDb.dbName),
    );
  });

  test(
    'regression: historical sleep correction preserves absolute instants in the recorded zone',
    () {
      final zone = dayZoneLocation('Asia/Tokyo');
      final onset = tz.TZDateTime(zone, 2026, 9, 10, 23);
      final expectedWake = tz.TZDateTime(zone, 2026, 9, 11, 7);
      final (start, end) = correctedSleepWindow(
        onset,
        const TimeOfDay(hour: 23, minute: 0),
        const TimeOfDay(hour: 7, minute: 0),
      );
      // No wall-clock change was requested, but the helper returns the current
      // OS timezone rather than the input's persisted IANA zone.
      expect(start.hour, 23);
      expect(start.millisecondsSinceEpoch, onset.millisecondsSinceEpoch);
      expect(end.millisecondsSinceEpoch, expectedWake.millisecondsSinceEpoch);
    },
  );

  test(
    'regression: cancelling multi-file restore leaves the live photo library untouched',
    () async {
      final source = Directory(p.join(tmp.path, 'source'))..createSync();
      final fakeDb = File(p.join(source.path, 'snapshot.db'))
        ..writeAsStringSync('synthetic database bytes');
      final photos = Directory(p.join(source.path, 'photos'))..createSync();
      const name = 'A1B2C3D4-0000-4000-8000-000000000095.jpg';
      File(p.join(photos.path, name)).writeAsBytesSync([1, 2, 3, 4]);
      final zip = await packMediaBackup(fakeDb.path, photos.path);
      final first = File(p.join(source.path, 'first.osbk'));
      final second = File(p.join(source.path, 'second.osbk'));
      for (final dest in [first, second]) {
        await encryptBackupFile(
          File(zip),
          dest,
          'synthetic passphrase',
          iterations: 1000,
          version: kBackupFormatVersionMedia,
        );
      }
      var prompts = 0;
      final app = AppState.forTesting();
      try {
        await expectLater(
          runImport(
            app,
            [first.path, second.path],
            askPassphrase: () async =>
                ++prompts == 1 ? 'synthetic passphrase' : null,
          ),
          throwsA(isA<PassphraseCancelled>()),
        );
        final photo = File(p.join((await BodyLogDb.photoDir()).path, name));
        expect(photo.existsSync(), isFalse);
        expect(await db.query('body_photo'), isEmpty);
        expect(
          tmp.listSync().whereType<File>().where(
            (f) => p.basename(f.path).startsWith('restore-'),
          ),
          isEmpty,
        );
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'regression: accepted media restore publishes referenced photos after the database',
    () async {
      final source = Directory(p.join(tmp.path, 'accepted-source'))
        ..createSync();
      final srcPath = p.join(source.path, 'snapshot.db');
      final src = await databaseFactory.openDatabase(srcPath);
      const id = 'A1B2C3D4-0000-4000-8000-000000000096';
      await src.execute(
        'CREATE TABLE body_photo(id TEXT PRIMARY KEY,date TEXT,pose TEXT,recorded_at INTEGER,source TEXT,created_at INTEGER)',
      );
      await src.insert('body_photo', {
        'id': id,
        'date': '2026-09-10',
        'pose': 'front',
        'recorded_at': 1,
        'source': 'whoop',
        'created_at': 1,
      });
      await src.close();
      final photos = Directory(p.join(source.path, 'photos'))..createSync();
      File(p.join(photos.path, '$id.jpg')).writeAsBytesSync([1, 2, 3]);
      File(
        p.join(photos.path, 'A1B2C3D4-0000-4000-8000-000000000097.jpg'),
      ).writeAsBytesSync([4, 5, 6]);
      final zip = await packMediaBackup(srcPath, photos.path);
      final sealed = File(p.join(source.path, 'accepted.osbk'));
      await encryptBackupFile(
        File(zip),
        sealed,
        'synthetic passphrase',
        iterations: 1000,
        version: kBackupFormatVersionMedia,
      );
      final app = AppState.forTesting();
      try {
        await runImport(app, [
          sealed.path,
        ], askPassphrase: () async => 'synthetic passphrase');
        expect((await db.query('body_photo')).single['id'], id);
        final live = await BodyLogDb.photoDir();
        expect(await File(p.join(live.path, '$id.jpg')).readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect(
          await File(
            p.join(live.path, 'A1B2C3D4-0000-4000-8000-000000000097.jpg'),
          ).exists(),
          false,
        );
        expect(
          tmp.listSync().where(
            (f) => p.basename(f.path).startsWith('restore-'),
          ),
          isEmpty,
        );
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'regression: reset invalidates an in-flight backup publication',
    () async {
      final captured = Completer<void>(), release = Completer<void>();
      final snapshot = File(p.join(tmp.path, 'pre-reset.db'))
        ..writeAsStringSync('synthetic');
      final pending = runBackup(
        passphrase: () async => 'synthetic passphrase',
        iterations: 1000,
        exportSnapshot: () async {
          captured.complete();
          await release.future;
          return snapshot.path;
        },
      );
      await captured.future;
      var deleted = false;
      final resetting = withoutBackupsDuringReset(() async {
        deleted = true;
      });
      expect(
        deleted,
        false,
        reason: 'Deletion must wait for the existing writer',
      );
      release.complete();
      final outcome = await pending;
      await resetting;
      expect(deleted, true);
      expect(outcome.skipped, true);
      final dir = await backupDirectory();
      expect(sortBackupsNewestFirst(dir.listSync()), isEmpty);
      expect(await snapshot.exists(), false);
    },
  );

  test(
    'regression: final-session write failure leaves resumable draft with closed recording clock',
    () async {
      final app = AppState.forTesting()..user = {'weight_kg': 70.0};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      final start = DateTime.now().subtract(const Duration(minutes: 3));
      const id = 'late-final-save-synthetic';
      await LocalDb.putSession({
        'id': id,
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'type': 'swimming',
        'status': 'live',
        'created_at': 1,
      });
      app.activeWorkout = LiveWorkoutState(
        startTime: start,
        targetKcal: 300,
        workoutId: id,
        type: 'swimming',
        profile: const Profile(weightKg: 70),
      );
      final clock = WorkoutClock.begin(id, start, const Profile(weightKg: 70));
      LiveDraft.begin(activityByName('Swimming')!);
      await db.execute(
        "CREATE TRIGGER audit_final_save_fail BEFORE INSERT ON sessions WHEN NEW.status='done' BEGIN SELECT RAISE(ABORT,'audit final save failure'); END",
      );
      try {
        await expectLater(
          app.stopWorkout(),
          throwsA(predicate((e) => '$e'.contains('audit final save failure'))),
        );
        expect(app.activeWorkout, isNotNull);
        expect(LiveDraft.current, isNotNull);
        expect((await LocalDb.session(id))!['status'], 'live');
        expect(clock.end, isNotNull);
        expect(app.workoutAwaitingSave, true);
        expect(LiveDraft.current!.elapsedSec, clock.activeSeconds(clock.end!));
        await db.execute('DROP TRIGGER audit_final_save_fail');
        await app.stopWorkout();
        expect(app.activeWorkout, isNull);
        expect((await LocalDb.session(id))!['status'], 'done');
        expect(
          clock.activeSeconds(clock.end!.add(const Duration(minutes: 5))),
          clock.activeSeconds(clock.end!),
        );
      } finally {
        await db.execute('DROP TRIGGER IF EXISTS audit_final_save_fail');
        app.activeWorkout = null;
        WorkoutClock.current = null;
        LiveDraft.clear();
        app.dispose();
      }
    },
  );

  test(
    'regression: same-day tape chart and estimate both use the latest reading',
    () async {
      const date = '2026-09-10';
      await BodyLogDb.putMeasure(
        BodyMeasure(
          id: 'synthetic-tape-early',
          date: date,
          recordedAt: DateTime(2026, 9, 10, 8),
          inches: {BodySite.waistNavel.name: 34},
        ),
      );
      await BodyLogDb.putMeasure(
        BodyMeasure(
          id: 'synthetic-tape-late',
          date: date,
          recordedAt: DateTime(2026, 9, 10, 12),
          inches: {BodySite.waistNavel.name: 35},
        ),
      );
      final measures = await BodyLogDb.measures();
      final series = siteSeries(measures, BodySite.waistNavel);
      final chart = {for (final point in series) point.date: point.value};
      expect(measures.first.value(BodySite.waistNavel), 35);
      expect(chart[date], 35);
      expect(bodySummary(series)!.latest.value, 35);
    },
  );

  test(
    'regression: private sessions stay in history and out of summary totals',
    () async {
      final start =
          DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000;
      await LocalDb.putSession({
        'id': 'private-summary-synthetic',
        'start_ts': start,
        'end_ts': start + 600,
        'duration_min': 10,
        'type': 'swimming',
        'status': 'done',
        'private': 1,
        'created_at': 1,
      });
      final repo = LocalRepositoryImpl(
        getProfileMap: () => {'weight_kg': 70.0},
      );
      final result = await repo.getWorkouts(range: 'all');
      expect((result['workouts'] as List).single['private'], true);
      expect((result['summary'] as Map)['count'], 0);
    },
  );

  test(
    'regression: older saved last-set traces discard out-of-window stats',
    () async {
      final start = DateTime(2026, 9, 10, 8);
      const id = 'synthetic-legacy-cut';
      await LocalDb.putSession({
        'id': id,
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'end_ts':
            start.add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
            1000,
        'type': 'weight_training',
        'status': 'done',
        'duration_min': 10,
        'strain': 19,
        'calories': 999,
        'avg_hr': 160,
        'max_hr': 180,
        'created_at': 1,
      });
      final clock = WorkoutClock.begin(id, start, const Profile(weightKg: 70));
      clock.results['hr'] = [null, 80, ...List<double?>.filled(13, null), 150];
      clock.results['zones'] = [0, 0, 0, 0, 15];
      clock.finish(start.add(const Duration(minutes: 10)));
      await clock.persist();
      WorkoutClock.current = null;
      final repo = LocalRepositoryImpl(
        getProfileMap: () => {'weight_kg': 70.0},
      );
      final result = await repo.getWorkout(id);
      expect(result['strain'], isNull);
      expect(result['calories'], isNull);
      expect(result['max_hr'], isNull);
      expect(result['zone_min'], isEmpty);
      final hr = result['hr'] as List;
      expect(hr.single['v'], 80);
      expect((await LocalDb.session(id))!['calories'], isNull);
      expect(
        WorkoutClock.read(
          id,
          start,
          end: start.add(const Duration(minutes: 10)),
        ).results['hr'],
        hasLength(10),
      );
    },
  );

  test(
    'regression: finish at last set trims the trace to its actual endpoint',
    () async {
      final app = AppState.forTesting()..user = {'weight_kg': 70.0};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      final start = DateTime.now().subtract(const Duration(minutes: 20));
      const id = 'last-set-shortened-synthetic';
      await LocalDb.putSession({
        'id': id,
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'type': 'weight_training',
        'status': 'live',
        'created_at': 1,
      });
      final w = LiveWorkoutState(
        startTime: start,
        targetKcal: 300,
        workoutId: id,
        type: 'weight_training',
        profile: const Profile(weightKg: 70),
      );
      w.elapsed = const Duration(minutes: 1);
      w.accrueHr(80);
      w.elapsed = const Duration(minutes: 15);
      w.accrueHr(150);
      app.activeWorkout = w;
      final clock = WorkoutClock.begin(id, start, const Profile(weightKg: 70));
      clock.finish(start.add(const Duration(minutes: 10)));
      // The next live tick may already have clamped the visible elapsed time;
      // it must not hide the out-of-window samples retained by the accumulator.
      w.elapsed = const Duration(minutes: 10);
      try {
        await app.stopWorkout();
        final row = (await LocalDb.session(id))!;
        expect(row['duration_min'], 10);
        final hr = clock.results['hr'] as List;
        expect(hr.length, lessThanOrEqualTo(10));
        expect(hr.whereType<num>(), [80]);
      } finally {
        app.activeWorkout = null;
        WorkoutClock.current = null;
        app.dispose();
      }
    },
  );
}
