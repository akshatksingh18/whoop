// Pull refresh keeps a live workout's calculation hold and reports partial failure.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

class Band extends BleEngine {
  Band() : super(onRecord: (_, _) async {}, onState: (_) {});
  bool connected = false;
  @override
  bool get isConnected => connected;
}

class App extends AppState {
  App(Band band) : super.forTesting(engine: band);
  var reconnects = 0, pulls = 0;
  @override
  Future<void> syncNow() async {
    reconnects++;
  }

  @override
  Future<void> foregroundCatchUp() async {
    pulls++;
    throw StateError('synthetic band pull refusal');
  }
}

class Reader extends LocalRepositoryImpl {
  Reader()
    : super(
        getProfileMap: () => {
          'age': 30,
          'sex': 'f',
          'weight_kg': 70,
          'height_cm': 170,
        },
      );
  bool refuse = false;
  @override
  Future<WorkoutRoute?> getWorkoutRoute(String id) async {
    if (refuse) throw StateError('synthetic retained movement read refusal');
    return super.getWorkoutRoute(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('pull-workout-hold'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in ['disconnected', 'band-refused', 'movement-refused']) {
    test(
      'pull during a workout reports $mode without inventing fresh totals or ending the session',
      () async {
        final band = Band()..connected = mode == 'band-refused';
        final app = App(band)
          ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
        final repo = Reader()..refuse = mode == 'movement-refused';
        app.repo = repo;
        try {
          expect(
            await app.startWorkout(
              type: 'general_workout',
              workoutId: 'synthetic-held',
            ),
            true,
          );
          final revision = app.insightsRevision.value;
          final note = await app.pullRefresh(
            timeout: const Duration(seconds: 2),
          );
          expect(
            note,
            contains(switch (mode) {
              'disconnected' => 'Band not connected',
              'band-refused' => 'Band sync could not finish',
              _ => 'Could not finish refreshing',
            }),
          );
          if (mode != 'movement-refused') {
            expect(
              note,
              contains('Other totals update after the workout ends.'),
            );
            expect(app.insightsRevision.value, greaterThan(revision));
          }
          expect(app.activeWorkout!.workoutId, 'synthetic-held');
          expect((await LocalDb.session('synthetic-held'))!['status'], 'live');
          expect(app.reconnects, mode == 'disconnected' ? 1 : 0);
          expect(app.pulls, mode == 'band-refused' ? 1 : 0);
        } finally {
          // Closing the fixture cancels held work; no local derive is launched.
          app.dispose();
          await WorkoutClock.flushWrites();
          WorkoutClock.current = null;
        }
      },
    );
  }
}
