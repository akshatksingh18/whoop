// Public route retry and live-feed callbacks, with synthetic SQLite history
// and a substituted geolocation platform. No physical GPS/permission claim.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/gps/gps_source.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/route_tracker.dart';
import 'package:openstrap_edge/gps/screen_wake.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
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
  @override
  Future<WorkoutRoute?> getWorkoutRoute(String id) async {
    reached?.complete();
    await wait?.future;
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
}
