// Real stored routes and public foreground refreshes. Hold only the existing
// repository read boundary; no GPS, private fields, heavy derive or invented data.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

class HeldMovementRead extends LocalRepositoryImpl {
  HeldMovementRead({this.refuseFirst = false})
    : super(getProfileMap: () => {'weight_kg': 70.0});
  final bool refuseFirst;
  final reached = Completer<void>(), release = Completer<void>();
  int reads = 0;
  @override
  Future<WorkoutRoute?> getWorkoutRoute(String id) async {
    final ordinal = ++reads;
    final snapshot = await super.getWorkoutRoute(id);
    if (ordinal == 1) {
      reached.complete();
      await release.future;
      if (refuseFirst) throw StateError('authored movement read refusal');
    }
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late HeldMovementRead reads;
  late DateTime start;
  const id = 'authored-overlap-movement';
  setUpAll(() => coverageStore('workout-movement-refresh'));
  setUp(() async {
    await resetCoverageStore();
    start = DateTime.now().subtract(const Duration(minutes: 2));
    await LocalDb.putSession({
      'id': id,
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'type': 'running',
      'status': 'live',
      'source': 'manual',
      'created_at': 1,
    });
    app = AppState.forTesting();
    app.activeWorkout = LiveWorkoutState(
      startTime: start,
      targetKcal: 300,
      workoutId: id,
      type: 'running',
      profile: const Profile(weightKg: 70),
    );
    WorkoutClock.begin(id, start, const Profile(weightKg: 70));
  });
  tearDown(() async {
    if (!reads.release.isCompleted) reads.release.complete();
    app.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
  });
  tearDownAll(LocalDb.close);

  Future<List<Map<String, dynamic>>> addRoute() async {
    await LocalDb.appendRoutePoints(id, [
      for (var i = 0; i < 2; i++)
        RoutePoint(
          seq: i,
          tsMs: start
              .add(Duration(seconds: 10 + i * 60))
              .millisecondsSinceEpoch,
          lat: 0,
          lng: i * .001,
          alt: 0,
          accuracy: 5,
          speed: 1.85,
        ).toRow(id),
    ]);
    return LocalDb.routePoints(id);
  }

  test(
    'a second fresh refresh reads route data arriving after the held snapshot',
    () async {
      app.repo = reads = HeldMovementRead();
      final session = await LocalDb.session(id);
      final first = app.refreshForeground();
      await reads.reached.future;
      final retained = await addRoute();
      final second = app.refreshForeground();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads.reads, 1);
      expect(app.liveDistanceKm, isNull);
      reads.release.complete();
      await Future.wait([first, second]);
      expect(reads.reads, 2);
      expect(app.liveDistanceKm, closeTo(.1112, .001));
      expect(await LocalDb.routePoints(id), retained);
      expect(await LocalDb.session(id), session);
      expect(await (await LocalDb.instance).query('day_result'), isEmpty);
    },
  );

  test(
    'a refused held read fails both waiters honestly and a fresh retry preserves the route',
    () async {
      app.repo = reads = HeldMovementRead(refuseFirst: true);
      final session = await LocalDb.session(id);
      final first = app.refreshForeground();
      await reads.reached.future;
      final retained = await addRoute();
      final second = app.refreshForeground();
      final a = expectLater(first, throwsStateError);
      final b = expectLater(second, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads.reads, 1);
      reads.release.complete();
      await Future.wait([a, b]);
      expect(reads.reads, 1);
      expect(app.liveDistanceKm, isNull);
      expect(await LocalDb.routePoints(id), retained);
      await app.refreshForeground();
      expect(reads.reads, 2);
      expect(app.liveDistanceKm, closeTo(.1112, .001));
      expect(await LocalDb.routePoints(id), retained);
      expect(await LocalDb.session(id), session);
      expect(await (await LocalDb.instance).query('day_result'), isEmpty);
    },
  );
}
