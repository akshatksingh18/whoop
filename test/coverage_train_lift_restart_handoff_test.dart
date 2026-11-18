import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';

import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('train-lift-restart-handoff', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets('Train finishes a retained Lift log at the linked workout end', (
    t,
  ) async {
    final started = DateTime(2021, 4, 6, 12);
    final ended = started.add(const Duration(minutes: 25));
    const id = 'authored-workout-finished-before-lift';
    await LocalDb.putSession({
      'id': id,
      'type': 'weightlifting',
      'status': 'done',
      'start_ts': started.millisecondsSinceEpoch ~/ 1000,
      'end_ts': ended.millisecondsSinceEpoch ~/ 1000,
      'created_at': started.millisecondsSinceEpoch,
      'source': 'manual',
      'duration_min': 25,
    });
    final workout = await LocalDb.session(id);
    final log = LiftWorkout(
      id: 'authored-open-set-log',
      startedAt: started,
      sessionId: id,
    );
    final exercise = log.addExercise(
      name: 'Authored press',
      loadMode: LiftLoadMode.total,
    );
    log.addSet(
      exercise,
      reps: 5,
      load: 20,
      at: started.add(const Duration(minutes: 15)),
    );
    await LiftLogDb.save(log);
    expect((await LiftLogDb.forSession(id))!.isActive, isTrue);
    final unrelated = LiftWorkout(
      id: 'authored-unrelated-log',
      startedAt: started,
      endedAt: ended,
    );
    await LiftLogDb.save(unrelated);
    final prior = (await LiftLogDb.finished(
      includePrivate: true,
    )).single.toJson();
    final service = NotificationService.instance;
    final originalCancel = service.debugCancel;
    service.debugCancel = (_) async {};
    addTearDown(() => service.debugCancel = originalCancel);
    final app = AppState.forTesting()
      ..repo = LocalRepositoryImpl(getProfileMap: () => {});
    addTearDown(app.dispose);

    await localizedPage(t, const WorkoutScreen(), app: app, settle: false);
    await io(t);
    expect(find.text('Train'), findsOneWidget);
    final saved = await LiftLogDb.forSession(id);
    expect(saved?.endedAt, ended);
    expect(saved?.exercises.single.toJson(), log.exercises.single.toJson());
    expect(saved?.setCount, 1);
    expect(await LiftLogDb.active(), isNull);
    expect(await LocalDb.session(id), workout);
    final preserved = (await LiftLogDb.finished(
      includePrivate: true,
    )).singleWhere((w) => w.id == unrelated.id);
    expect(preserved.toJson(), prior);
    expect(t.takeException(), isNull);
  });
}
