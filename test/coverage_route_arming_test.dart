// Public route retry and live-feed callbacks, with synthetic SQLite history
// and a substituted geolocation platform. No physical GPS/permission claim.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/gps_source.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/route_tracker.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Geo extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast();
  bool service = true, fail = false, throwStream = false;
  LocationPermission permission = LocationPermission.whileInUse;
  Future<bool>? serviceWait;
  var checks = 0, streams = 0, settings = 0;
  @override
  Future<bool> isLocationServiceEnabled() async {
    checks++;
    if (fail) throw StateError('synthetic location service error');
    return serviceWait == null ? service : await serviceWait!;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<bool> openAppSettings() async {
    settings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    settings++;
    return true;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streams++;
    if (throwStream) throw StateError('synthetic stream setup error');
    return positions.stream;
  }
}

class _RouteReads extends LocalRepositoryImpl {
  _RouteReads() : super(getProfileMap: () => {'weight_kg': 70.0});
  bool fail = false;
  Completer<void>? reached, wait;
  Future<void> Function()? beforeRead;
  @override
  Future<WorkoutRoute?> getWorkoutRoute(String id) async {
    reached?.complete();
    await wait?.future;
    await beforeRead?.call();
    if (fail) throw StateError('synthetic saved-route read failure');
    return super.getWorkoutRoute(id);
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late _Geo geo;
  late GeolocatorPlatform original;
  late Directory root;
  RouteTracker? tracker;
  var disposed = false;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = (await Directory(
      'build/coverage-remainder/route-arming',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    ScreenWake.resetForTest();
    original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = geo = _Geo();
    app = AppState.forTesting();
    app.repo = LocalRepositoryImpl(getProfileMap: () => {'weight_kg': 70.0});
    final start = DateTime.now().subtract(const Duration(minutes: 2));
    await LocalDb.putSession({
      'id': 'synthetic-live-route',
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'type': 'running',
      'status': 'live',
      'source': 'manual',
      'created_at': 1,
    });
    app.activeWorkout = LiveWorkoutState(
      startTime: start,
      targetKcal: 300,
      workoutId: 'synthetic-live-route',
      type: 'running',
      profile: const Profile(weightKg: 70),
    );
    WorkoutClock.begin(
      'synthetic-live-route',
      start,
      const Profile(weightKg: 70),
    );
    disposed = false;
    tracker = null;
  });
  tearDown(() async {
    tracker ??= app.routeTracker;
    if (tracker != null) await tracker!.stop();
    if (!disposed) app.dispose();
    WorkoutClock.current = null;
    await geo.positions.close();
    GeolocatorPlatform.instance = original;
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS refuse_route_tail',
    );
    await FileLog.write('Synthetic route arming barrier');
    ScreenWake.resetForTest();
  });
  tearDownAll(LocalDb.close);

  test(
    'disposing an armed route cancels GPS and saves its buffered tail',
    () async {
      await app.retryRouteTracking();
      tracker = app.routeTracker!;
      geo.positions.add(
        Position(
          longitude: 0,
          latitude: 0,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 1,
          heading: 0,
          headingAccuracy: 1,
          speed: 1,
          speedAccuracy: 0.2,
        ),
      );
      await settle();
      expect(tracker!.pointCount, 1);
      await ScreenWake.enable();
      app.dispose();
      disposed = true;
      await settle();
      expect(geo.positions.hasListener, false);
      expect(ScreenWake.isHeld, false);
      expect(await LocalDb.routePoints('synthetic-live-route'), hasLength(1));
      expect(
        (await LocalDb.session('synthetic-live-route'))!['status'],
        'live',
      );
      expect(
        WorkoutClock.current!.end,
        isNull,
        reason: 'Dispose stops resources; it must not invent a workout finish',
      );
    },
  );

  test(
    'the live feed Try again retries a location error instead of opening Settings',
    () async {
      geo.fail = true;
      await app.retryRouteTracking();
      expect(app.routeLocationIssue, GpsPermissionStatus.error);
      geo.fail = false;
      activityHost(app).feed!().onFixRoute!();
      await settle();
      expect(geo.settings, 0);
      expect(geo.checks, 2);
      expect(app.routeTracker, isNotNull);
      expect(app.routeLocationIssue, isNull);
    },
  );

  for (final issue in ['service off', 'denied', 'permanent denial', 'error']) {
    test('$issue keeps the workout live without inventing a route', () async {
      geo.service = issue != 'service off';
      geo.fail = issue == 'error';
      geo.permission = switch (issue) {
        'denied' => LocationPermission.denied,
        'permanent denial' => LocationPermission.deniedForever,
        _ => LocationPermission.whileInUse,
      };
      await app.retryRouteTracking();
      expect(app.routeLocationIssue, switch (issue) {
        'service off' => GpsPermissionStatus.serviceOff,
        'denied' => GpsPermissionStatus.denied,
        'permanent denial' => GpsPermissionStatus.deniedForever,
        _ => GpsPermissionStatus.error,
      });
      expect(app.routeTracker, isNull);
      expect(geo.streams, 0);
      expect(app.activeWorkout?.workoutId, 'synthetic-live-route');
      expect(await LocalDb.routePoints('synthetic-live-route'), isEmpty);
    });
  }

  for (final cancel in ['finish', 'change workout', 'dispose']) {
    test('permission returning after $cancel cannot arm GPS', () async {
      final wait = Completer<bool>();
      geo.serviceWait = wait.future;
      final pending = app.retryRouteTracking();
      await settle();
      if (cancel == 'finish') {
        WorkoutClock.current!.finish(DateTime.now());
      } else if (cancel == 'change workout') {
        app.activeWorkout = null;
      } else {
        app.dispose();
        disposed = true;
      }
      wait.complete(true);
      await pending;
      expect(app.routeTracker, isNull);
      expect(geo.streams, 0);
    });
  }

  test(
    'concurrent route retries create one tracker and retain earlier points',
    () async {
      const id = 'synthetic-live-route';
      final start = app.activeWorkout!.startTime.millisecondsSinceEpoch;
      final old = RoutePoint(seq: 8, tsMs: start, lat: 0, lng: 0, accuracy: 5);
      final second = RoutePoint(
        seq: 9,
        tsMs: start + 1000,
        lat: 0,
        lng: 0.0001,
        accuracy: 5,
      );
      await LocalDb.appendRoutePoints(id, [old.toRow(id), second.toRow(id)]);
      await Future.wait([app.retryRouteTracking(), app.retryRouteTracking()]);
      expect(geo.streams, 1);
      expect(app.routeTracker!.acceptedPoints.map((p) => p.seq), [8, 9]);
      await app.retryRouteTracking();
      expect(geo.streams, 1);
      expect((await LocalDb.routePoints(id)).map((p) => p['seq']), [8, 9]);
    },
  );

  test('stream setup failure can retry without ending the workout', () async {
    geo.throwStream = true;
    await app.retryRouteTracking();
    expect(app.routeLocationIssue, GpsPermissionStatus.error);
    expect(app.routeTracker, isNull);
    geo.throwStream = false;
    await app.retryRouteTracking();
    expect(app.routeLocationIssue, isNull);
    expect(geo.streams, 2);
    expect(app.routeTracker!.isRunning, true);
  });

  test('a paused session arms its route tracker paused', () async {
    WorkoutClock.current!.setPaused(true);
    await app.retryRouteTracking();
    expect(app.routeTracker!.paused, true);
    expect(app.activeWorkout, isNotNull);
  });

  test(
    'saved route read failure stays unarmed and the same action can retry',
    () async {
      final reads = _RouteReads()..fail = true;
      app.repo = reads;
      await app.retryRouteTracking();
      expect(app.routeLocationIssue, GpsPermissionStatus.error);
      expect(app.routeTracker, isNull);
      expect(geo.streams, 0);
      reads.fail = false;
      activityHost(app).feed!().onFixRoute!();
      await settle();
      expect(app.routeTracker, isNotNull);
      expect(app.routeLocationIssue, isNull);
      expect(
        (await LocalDb.session('synthetic-live-route'))!['status'],
        'live',
      );
    },
  );

  for (final ending in ['finish', 'delete', 'dispose']) {
    for (final failRead in [false, true]) {
      test(
        'saved route ${failRead ? 'failure' : 'read'} returning after $ending cannot arm GPS',
        () async {
          final reads = _RouteReads()
            ..fail = failRead
            ..reached = Completer<void>()
            ..wait = Completer<void>();
          app.repo = reads;
          final pending = app.retryRouteTracking();
          await reads.reached!.future;
          if (ending == 'finish') {
            WorkoutClock.current!.finish(DateTime.now());
          } else if (ending == 'delete') {
            await app.deleteWorkout('synthetic-live-route');
          } else {
            app.dispose();
            disposed = true;
          }
          reads.wait!.complete();
          await pending;
          expect(geo.streams, 0);
          expect(app.routeTracker, isNull);
        },
      );
    }
  }

  test('a disposed app cannot prompt for route permissions again', () async {
    app.dispose();
    disposed = true;
    await app.retryRouteTracking();
    expect(geo.checks, 0);
    expect(geo.streams, 0);
  });

  for (final mode in [
    (type: 'running', speed: 3.0, qualified: true),
    (type: 'walking', speed: 1.2, qualified: true),
    (type: 'walking', speed: 2.5, qualified: false),
  ]) {
    test(
      'live ${mode.type} route at ${mode.speed} m/s retains estimate qualification',
      () async {
        final clock = WorkoutClock.current!;
        await (await LocalDb.instance).update(
          'sessions',
          {'type': mode.type},
          where: 'id=?',
          whereArgs: [clock.id],
        );
        app.activeWorkout = LiveWorkoutState(
          startTime: clock.start,
          targetKcal: 300,
          workoutId: clock.id,
          type: mode.type,
          profile: const Profile(weightKg: 70),
        );
        await app.retryRouteTracking();
        tracker = app.routeTracker!;
        // Seven authored fixes on a straight equatorial line, ten seconds apart.
        // Use real platform -> GPS source -> tracker callbacks, never private fields.
        for (var i = 0; i < 7; i++) {
          geo.positions.add(
            Position(
              longitude: i * mode.speed * 10 / 111195,
              latitude: 0,
              timestamp: clock.start.add(Duration(seconds: 60 + i * 10)),
              accuracy: 5,
              altitude: 0,
              altitudeAccuracy: 1,
              heading: 90,
              headingAccuracy: 1,
              speed: mode.speed,
              speedAccuracy: .2,
            ),
          );
          await settle();
        }
        expect(tracker!.pointCount, 7);
        expect(app.trackerDistanceKm, closeTo(mode.speed * 60 / 1000, .001));
        expect(app.workoutMovementEstimateKcal, greaterThan(0));
        expect(app.workoutAcsmKcal, mode.qualified ? greaterThan(0) : isNull);
        expect(
          app.workoutActiveKcal,
          mode.type == 'running' ? greaterThan(0) : isNull,
          reason: 'approved walking Method 1 still requires measured steps',
        );
        expect(
          app.workoutHrActiveKcal,
          isNull,
          reason: 'route distance cannot invent a heart-rate reading',
        );
        expect(app.activeWorkout!.profile.weightKg, 70);
        expect(clock.end, isNull);
        expect(clock.spokenKm, 0);
        await tracker!.stop();
        expect(await LocalDb.routePoints(clock.id), hasLength(7));
        expect((await LocalDb.session(clock.id))!['status'], 'live');
      },
    );
  }

  test(
    'disposal contains a failed final route save and still releases resources',
    () async {
      await app.retryRouteTracking();
      tracker = app.routeTracker!;
      geo.positions.add(
        Position(
          longitude: 0,
          latitude: 0,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 1,
          heading: 0,
          headingAccuracy: 1,
          speed: 1,
          speedAccuracy: 0.2,
        ),
      );
      await settle();
      await (await LocalDb.instance).execute(
        "CREATE TRIGGER refuse_route_tail BEFORE INSERT ON workout_route BEGIN SELECT RAISE(ABORT,'synthetic final route save failure'); END",
      );
      await ScreenWake.enable();
      app.dispose();
      disposed = true;
      await settle();
      expect(geo.positions.hasListener, false);
      expect(ScreenWake.isHeld, false);
      expect(
        app.logLines.any(
          (s) => s.contains('final save during disposal failed'),
        ),
        true,
      );
      expect(
        (await LocalDb.session('synthetic-live-route'))!['status'],
        'live',
      );
      expect(await LocalDb.routePoints('synthetic-live-route'), isEmpty);
    },
  );

  Position fix({double longitude = 0, DateTime? at}) => Position(
    longitude: longitude,
    latitude: 0,
    timestamp: at ?? DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 90,
    headingAccuracy: 1,
    speed: 2,
    speedAccuracy: .2,
  );

  test(
    'COV-48 actual live host separates armed GPS from a fresh fix',
    () async {
      final row = await LocalDb.session('synthetic-live-route');
      await app.retryRouteTracking();
      final host = activityHost(app);
      final waiting = host.feed!();
      expect(waiting.gpsWaiting, true);
      expect(waiting.gpsActive, false);
      expect(waiting.currentSpeedMps, isNull);
      expect(waiting.currentSpeedAccuracyMps, isNull);
      geo.positions.add(fix());
      await settle();
      final moving = host.feed!();
      expect(moving.gpsWaiting, false);
      expect(moving.gpsActive, true);
      expect(moving.currentSpeedMps, 2);
      expect(moving.currentSpeedAccuracyMps, .2);
      expect(moving.distanceKm, 0);
      expect(moving.hr, isNull);
      expect(moving.steps, isNull);
      expect(moving.hrActiveCalories, isNull);
      expect(await LocalDb.session('synthetic-live-route'), row);
      await app.routeTracker!.stop();
      expect(await LocalDb.routePoints('synthetic-live-route'), hasLength(1));
    },
  );

  for (final issue in ['service off', 'permanent denial']) {
    test('COV-48 actual live host sends $issue to Settings once', () async {
      geo.service = issue != 'service off';
      geo.permission = issue == 'permanent denial'
          ? LocationPermission.deniedForever
          : LocationPermission.whileInUse;
      final row = await LocalDb.session('synthetic-live-route');
      await app.retryRouteTracking();
      activityHost(app).feed!().onFixRoute!();
      await settle();
      expect(geo.settings, 1);
      expect(geo.checks, 1);
      expect(geo.streams, 0);
      expect(app.routeTracker, isNull);
      expect(await LocalDb.session('synthetic-live-route'), row);
      expect(await LocalDb.routePoints('synthetic-live-route'), isEmpty);
    });
  }

  test('COV-48 final route flush finishes the actual session once', () async {
    const id = 'synthetic-live-route';
    final before = (await LocalDb.session(id))!;
    await app.retryRouteTracking();
    tracker = app.routeTracker!;
    final at = DateTime.now().subtract(const Duration(seconds: 10));
    geo.positions.add(fix(at: at));
    geo.positions.add(
      fix(at: at.add(const Duration(seconds: 10)), longitude: .0002),
    );
    await settle();
    expect(tracker!.pointCount, 2);
    expect(geo.positions.hasListener, true);
    await app.stopWorkout();
    expect(app.activeWorkout, isNull);
    expect(app.routeTracker, isNull);
    expect(app.routeLocationIssue, isNull);
    expect(geo.positions.hasListener, false);
    final saved = (await LocalDb.session(id))!;
    expect(saved['status'], 'done');
    expect(saved['start_ts'], before['start_ts']);
    expect(saved['type'], before['type']);
    expect(saved['steps'], isNull);
    final points = await LocalDb.routePoints(id);
    expect(points, hasLength(2));
    expect(points.map((r) => r['lng']), [0, .0002]);
    await app.stopWorkout();
    expect(await LocalDb.session(id), saved);
    expect(await LocalDb.routePoints(id), points);
  });

  test(
    'COV-48 route sequence read refusal cannot overwrite retained points',
    () async {
      const id = 'synthetic-live-route';
      final at = DateTime.now().subtract(const Duration(seconds: 20));
      final old = RoutePoint(
        seq: 8,
        tsMs: at.millisecondsSinceEpoch,
        lat: 0,
        lng: 0,
        accuracy: 5,
      );
      final second = RoutePoint(
        seq: 9,
        tsMs: at.millisecondsSinceEpoch + 10000,
        lat: 0,
        lng: .0001,
        accuracy: 5,
      );
      await LocalDb.appendRoutePoints(id, [old.toRow(id), second.toRow(id)]);
      final rows = await LocalDb.routePoints(id);
      final db = await LocalDb.instance;
      var restored = false;
      app.repo = _RouteReads()
        ..beforeRead = () async {
          await db.execute(
            'ALTER TABLE authored_route_sequence RENAME TO workout_route',
          );
          restored = true;
        };
      await db.execute(
        'ALTER TABLE workout_route RENAME TO authored_route_sequence',
      );
      try {
        await app.retryRouteTracking();
        expect(restored, true);
        tracker = app.routeTracker!;
        expect(tracker!.acceptedPoints.map((p) => p.seq), [8, 9]);
        geo.positions.add(fix(longitude: .0003));
        await settle();
        await tracker!.stop();
        final after = await LocalDb.routePoints(id);
        expect(after, hasLength(3));
        expect(after.take(2), rows);
        expect(after.last['seq'] as int, greaterThan(9));
        expect(after.last['lng'], .0003);
        expect((await LocalDb.session(id))!['status'], 'live');
      } finally {
        if (!restored) {
          await db.execute(
            'ALTER TABLE authored_route_sequence RENAME TO workout_route',
          );
        }
      }
    },
  );
}
