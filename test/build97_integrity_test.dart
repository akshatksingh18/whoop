// Restart, import and backup regressions. Every input is synthetic.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/body_photo_file.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/media_backup.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/import/backup_crypto.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = Directory('build/build97-test').absolute;
    await root.create(recursive: true);
    LocalDb.dbName = p.join(root.path, 'synthetic.sqlite');
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    tmp = await Directory('build/build97-test').absolute.createTemp('case-');
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    WorkoutClock.current = null;
    await LocalDb.wipeAll();
  });
  tearDown(() async {
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    await FileLog.write('Synthetic test cleanup barrier');
    await tmp.delete(recursive: true);
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });

  for (final oldClock in [false, true]) {
    test(
      'failed finish survives cold restart, including old stopped clock=$oldClock',
      () async {
        const id = 'synthetic-restart-save';
        const profile = Profile(
          ageYears: 30,
          weightKg: 70,
          heightCm: 175,
          sex: 'm',
        );
        final start = DateTime.now().subtract(
          Duration(hours: oldClock ? 9 : 0, minutes: 4),
        );
        final old = AppState.forTesting()..user = profile.toMap();
        old.repo = LocalRepositoryImpl(getProfileMap: () => old.user);
        await LocalDb.putSession({
          'id': id,
          'start_ts': start.millisecondsSinceEpoch ~/ 1000,
          'type': 'swimming',
          'status': 'live',
          'created_at': 1,
          'private': 1,
          'rpe': 7,
          'device_family': 'gen4',
        });
        final live = LiveWorkoutState(
          startTime: start,
          workoutId: id,
          targetKcal: 300,
          type: 'swimming',
          profile: profile,
          age: 30,
          restingHr: 60,
          hrMax: 190,
          met: 6,
        );
        for (var i = 0; i < 120; i++) {
          live.elapsed = Duration(seconds: i);
          live.accrueHr(i < 60 ? 140 : 150);
          live.zoneSeconds[3] += 1;
        }
        old.activeWorkout = live;
        final originalClock = WorkoutClock.begin(id, start, profile);
        originalClock.finish(start.add(const Duration(minutes: 4)));
        await WorkoutClock.flushWrites();
        await db.execute(
          "CREATE TRIGGER synthetic_finish_fail BEFORE INSERT ON sessions WHEN NEW.status='done' BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
        );
        addTearDown(
          () => db.execute('DROP TRIGGER IF EXISTS synthetic_finish_fail'),
        );
        await expectLater(old.stopWorkout(), throwsA(anything));
        final trace = List.of(originalClock.results['hr'] as List);
        final zones = List.of(originalClock.results['zones'] as List);
        final expected = originalClock.pendingSession!;
        expect(trace.whereType<num>(), isNotEmpty);
        expect(expected['avg_hr'], isNotNull);
        expect(expected['strain'], isNotNull);
        old.dispose();
        WorkoutClock.current = null;
        // Simulate a new preference cache, not only a new AppState instance.
        await (await SharedPreferences.getInstance()).reload();
        final fresh = AppState.forTesting()..user = {'weight_kg': 90};
        fresh.repo = LocalRepositoryImpl(getProfileMap: () => fresh.user);
        addTearDown(fresh.dispose);
        await fresh.debugReconcileOrphanedLiveWorkout();
        expect(fresh.workoutAwaitingSave, true);
        expect(WorkoutClock.current!.profile!.weightKg, 70);
        expect(WorkoutClock.current!.pendingSession, expected);
        await db.execute('DROP TRIGGER synthetic_finish_fail');
        await fresh.stopWorkout();
        final after = WorkoutClock.read(id, start);
        final row = (await LocalDb.session(id))!;
        for (final key in expected.keys) {
          expect(row[key], expected[key], reason: key);
        }
        expect(row['private'], 1);
        expect(row['rpe'], 7);
        expect(after.results['hr'], trace);
        expect(after.results['zones'], zones);
        expect(after.pendingSession, isNull);
        expect(fresh.activeWorkout, isNull);
      },
    );
  }

  Map<String, Object> photo(String id, {String day = '2026-09-02'}) => {
    'id': id,
    'day': day,
    'pose': 'front',
    'recordedAt': '2026-09-02T10:00:00Z',
  };
  String manifest({
    List<Object> weights = const [],
    List<Object> photos = const [],
    List<Object> measurements = const [],
    Object? baseline,
  }) => jsonEncode({
    'format': 'whoop-body-history',
    'version': 1,
    'weights': weights,
    'photos': photos,
    'measurements': measurements,
    if (baseline != null) 'baseline': {'date': baseline},
  });
  Future<void> noBodyRows() async {
    for (final table in [
      'body_weight',
      'body_weight_reading',
      'body_photo',
      'body_measure',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
  }

  test('duplicate photo IDs fail preflight before any writes', () async {
    await expectLater(
      planBodyImport(
        manifest(photos: [photo('same'), photo('same')]),
        files: {'same.jpg': 'synthetic.jpg'},
      ),
      throwsFormatException,
    );
    await noBodyRows();
  });

  test('stale preview and insert failure never alter an existing photo', () async {
    final plan = await planBodyImport(
      manifest(photos: [photo('safe_photo')]),
      files: {'safe_photo.jpg': 'synthetic.jpg'},
    );
    await applyBodyImport(plan, encode: (_) async => [1, 2, 3]);
    final file = await BodyLogDb.photoFile((await BodyLogDb.photos()).single);
    await expectLater(
      applyBodyImport(plan, encode: (_) async => [9, 9]),
      throwsA(anything),
    );
    expect(await file.readAsBytes(), [1, 2, 3]);
    // An orphan file also belongs to its current owner, not this attempted save.
    final orphan = File(p.join(file.parent.path, 'orphan.jpg'));
    await orphan.writeAsBytes([4, 5]);
    await expectLater(
      BodyLogDb.addPhoto([8], date: '2026-09-02', pose: 'front', id: 'orphan'),
      throwsA(anything),
    );
    expect(await orphan.readAsBytes(), [4, 5]);
    await db.execute(
      "CREATE TRIGGER synthetic_photo_fail BEFORE INSERT ON body_photo BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
    );
    try {
      await expectLater(
        BodyLogDb.addPhoto(
          [6],
          date: '2026-09-02',
          pose: 'front',
          id: 'new_photo',
        ),
        throwsA(anything),
      );
      expect(
        await File(p.join(file.parent.path, 'new_photo.jpg')).exists(),
        false,
      );
      expect(await file.readAsBytes(), [1, 2, 3]);
    } finally {
      await db.execute('DROP TRIGGER synthetic_photo_fail');
    }
  });

  test('concurrent publication cannot overwrite the winning photo', () async {
    final results = await Future.wait([
      for (final bytes in [
        [1, 2],
        [3, 4],
      ])
        BodyLogDb.addPhoto(
          bytes,
          date: '2026-09-02',
          pose: 'front',
          id: 'concurrent',
        ).then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(results.whereType<BodyPhoto>(), hasLength(1));
    final file = await BodyLogDb.photoFile((await BodyLogDb.photos()).single);
    expect(await file.readAsBytes(), anyOf(equals([1, 2]), equals([3, 4])));
  });

  test(
    'all imported date families reject normalization, valid leap dates survive',
    () async {
      for (final bad in [
        '2026-02-31',
        '2026-02-29',
        '2026-13-01',
        '2026-00-10',
        '2026-04-31',
      ]) {
        for (final text in [
          manifest(
            weights: [
              {'date': bad, 'unit': 'kg', 'value': 70},
            ],
          ),
          manifest(photos: [photo('date_photo', day: bad)]),
          manifest(
            measurements: [
              {
                'id': 'tape',
                'day': bad,
                'recordedAt': 1,
                'inches': {'neck': 15},
              },
            ],
          ),
          manifest(baseline: bad),
        ]) {
          await expectLater(planBodyImport(text), throwsA(anything));
        }
        await expectLater(
          BodyLogDb.putWeight(bad, 70, 'kg'),
          throwsA(isA<BodyLogError>()),
        );
      }
      await noBodyRows();
      final plan = await planBodyImport(
        manifest(
          weights: [
            {'date': '2024-02-29', 'unit': 'kg', 'value': 70},
          ],
        ),
      );
      await applyBodyImport(plan, encode: (_) async => []);
      expect((await BodyLogDb.weights()).single.date, '2024-02-29');
    },
  );

  test(
    'kg and lb preserve quantity; unsupported units fail before writing',
    () async {
      for (final unit in ['', 'stone', 'KG', 'oz']) {
        await expectLater(
          planBodyImport(
            manifest(
              weights: [
                {'date': '2026-09-02', 'unit': unit, 'value': 70},
              ],
            ),
          ),
          throwsA(isA<BodyLogError>()),
        );
        await expectLater(
          BodyLogDb.putWeight('2026-09-02', 70, unit),
          throwsA(isA<BodyLogError>()),
        );
      }
      await noBodyRows();
      expect(BodyLogDb.checkWeight(70 * kLbPerKg, 'lb'), closeTo(70, 1e-9));
      expect(BodyLogDb.checkWeight(70, 'kg'), 70);
    },
  );

  test(
    'safe legacy photos survive encrypted backup and real restore',
    () async {
      final ids = [
        'synthetic_photo',
        'short',
        'legacy.photo',
        'photo space',
        'photo_é',
      ];
      for (final id in ids) {
        final plan = await planBodyImport(
          manifest(photos: [photo(id)]),
          files: {'$id.jpg': 'synthetic.jpg'},
        );
        await applyBodyImport(plan, encode: (_) async => [1, 2, 3, id.length]);
      }
      final directory = await BodyLogDb.photoDir();
      expect(await mediaBackupPhotoCount(directory.path), ids.length);
      final snapshot = await LocalDb.exportCopy();
      final packed = await packMediaBackupWithCount(
        snapshot,
        directory.path,
        requiredPhotoNames: await mediaSnapshotPhotoNames(snapshot),
      );
      expect(packed.photos, ids.length);
      final sealed = File(p.join(tmp.path, 'synthetic.osbk'));
      await encryptBackupFile(
        File(packed.path),
        sealed,
        'synthetic passphrase',
        iterations: 1000,
        version: kBackupFormatVersionMedia,
      );
      await LocalDb.wipeAll();
      await directory.delete(recursive: true);
      final app = AppState.forTesting();
      try {
        await runImport(app, [
          sealed.path,
        ], askPassphrase: () async => 'synthetic passphrase');
        expect(
          (await BodyLogDb.photos()).map((p) => p.id).toSet(),
          ids.toSet(),
        );
        for (final ph in await BodyLogDb.photos()) {
          expect(await (await BodyLogDb.photoFile(ph)).readAsBytes(), [
            1,
            2,
            3,
            ph.id.length,
          ]);
        }
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'unsafe photo names reject preflight; missing referenced media is explicit',
    () async {
      for (final id in ['../escape', r'..\escape', 'bad:name', 'CON', '']) {
        expect(isBodyPhotoFileName('$id.jpg'), false);
        await expectLater(
          planBodyImport(manifest(photos: [photo(id)])),
          throwsFormatException,
        );
      }
      await noBodyRows();
      await expectLater(
        validateMediaPhotoFiles(tmp.path, ['missing.jpg']),
        throwsFormatException,
      );
    },
  );

  test(
    'media backup with zero images cannot restore dangling photo rows',
    () async {
      final photo = await BodyLogDb.addPhoto(
        [1, 2, 3],
        date: '2026-09-02',
        pose: 'front',
        id: 'synthetic_missing',
      );
      final snapshot = await LocalDb.exportCopy();
      final directory = await BodyLogDb.photoDir();
      await (await BodyLogDb.photoFile(photo)).delete();
      // Deliberately recreate the old malformed media payload, bypassing the
      // new export preflight. Restore must independently refuse it.
      final packed = await packMediaBackupWithCount(snapshot, directory.path);
      expect(packed.photos, 0);
      final sealed = File(p.join(tmp.path, 'missing.osbk'));
      await encryptBackupFile(
        File(packed.path),
        sealed,
        'synthetic passphrase',
        iterations: 1000,
        version: kBackupFormatVersionMedia,
      );
      await LocalDb.wipeAll();
      final app = AppState.forTesting();
      try {
        await expectLater(
          runImport(app, [
            sealed.path,
          ], askPassphrase: () async => 'synthetic passphrase'),
          throwsFormatException,
        );
        expect(await BodyLogDb.photos(), isEmpty);
      } finally {
        app.dispose();
      }
    },
  );
}
