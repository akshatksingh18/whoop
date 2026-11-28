// AppState background transition -> actual route buffer -> SQLite;authored GPS host.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_tracker.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import '../support/coverage_store.dart';

class _Geo extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast();
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      positions.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('background-route-tail'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refused in [false, true]) {
    test(
      'background route tail refusal=$refused keeps live ownership and retries exactly once',
      () async {
        final original = GeolocatorPlatform.instance, geo = _Geo();
        GeolocatorPlatform.instance = geo;
        final app = AppState.forTesting(
          isIOS: true,
        )..repo = LocalRepositoryImpl(getProfileMap: () => {'weight_kg': 70.0});
        RouteTracker? tracker;
        final db = await LocalDb.instance;
        const id = 'authored-background-route';
        final start = DateTime.now().subtract(const Duration(minutes: 2));
        try {
          await SessionStore.put({
            'id': id,
            'start_ts': start.millisecondsSinceEpoch ~/ 1000,
            'type': 'running',
            'status': 'live',
            'source': 'manual',
            'created_at': 1,
          });
          app.activeWorkout = LiveWorkoutState(
            startTime: start,
            targetKcal: 300,
            workoutId: id,
            type: 'running',
            profile: const Profile(weightKg: 70),
          );
          WorkoutClock.begin(id, start, const Profile(weightKg: 70));
          await app.retryRouteTracking();
          tracker = app.routeTracker!;
          expect(geo.positions.hasListener, true);
          final now = DateTime.now();
          for (var i = 0; i < 2; i++) {
            geo.positions.add(
              Position(
                longitude: i * .00004,
                latitude: 0,
                timestamp: now.add(Duration(seconds: i)),
                accuracy: 3,
                altitude: 0,
                altitudeAccuracy: 1,
                heading: 90,
                headingAccuracy: 1,
                speed: 4.4,
                speedAccuracy: .2,
              ),
            );
          }
          for (var i = 0; i < 50 && tracker.pointCount < 2; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(tracker.pointCount, 2);
          expect(await WorkoutRouteStore.points(id), isEmpty);
          if (refused) {
            await db.execute(
              "CREATE TRIGGER authored_refuse_background_route BEFORE INSERT ON workout_route BEGIN SELECT RAISE(ABORT, 'authored route refusal'); END",
            );
          }
          await app.pauseForBackground();
          for (var i = 0; i < 50; i++) {
            if (refused
                ? tracker.error.value != null
                : (await WorkoutRouteStore.points(id)).length == 2) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          if (refused) {
            expect(
              tracker.error.value,
              'Route could not be saved. Try finishing again.',
            );
            expect(await WorkoutRouteStore.points(id), isEmpty);
            expect(tracker.pointCount, 2);
            await db.execute('DROP TRIGGER authored_refuse_background_route');
            await tracker.flush();
            expect(tracker.error.value, isNull);
          }
          final rows = await WorkoutRouteStore.points(id);
          expect(rows.map((r) => r['seq']), [0, 1]);
          expect(rows.map((r) => r['ts_ms']), [
            now.millisecondsSinceEpoch,
            now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
          ]);
          await app.pauseForBackground();
          await tracker.flush();
          expect(await WorkoutRouteStore.points(id), rows);
          expect(app.activeWorkout!.workoutId, id);
          expect(WorkoutClock.current!.end, isNull);
          expect((await SessionStore.byId(id))!['status'], 'live');
          expect(geo.positions.hasListener, true);
          expect(app.deriving, false);
          expect(await db.query('day_result'), isEmpty);
          expect(await db.query('decoded_onehz'), isEmpty);
        } finally {
          await db.execute(
            'DROP TRIGGER IF EXISTS authored_refuse_background_route',
          );
          await tracker?.stop();
          app.dispose();
          await geo.positions.close();
          GeolocatorPlatform.instance = original;
          await WorkoutClock.flushWrites();
          WorkoutClock.current = null;
        }
      },
    );
  }
}
