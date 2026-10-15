import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/coach/coach_actions.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late String oldName;
  late AppState app;
  late LocalRepositoryImpl repo;
  late int initialInsights, initialFood;
  var signals = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    oldName = LocalDb.dbName;
    root = await Directory.systemTemp.createTemp('synthetic-session-signal-');
    LocalDb.dbName = '${root.path}/app.db';
    db = await LocalDb.instance;
    app = AppState.forTesting();
    signals = 0;
    initialInsights = app.insightsRevision.value;
    initialFood = NutritionDb.revision.value;
    repo = LocalRepositoryImpl(
      getProfileMap: () => null,
      onSessionChanged: () {
        signals++;
        app.publishSessionChange();
      },
    );
  });
  tearDown(() async {
    app.dispose();
    await LocalDb.close();
    LocalDb.dbName = oldName;
    await root.delete(recursive: true);
  });
  void published(int n) {
    expect(signals, n);
    expect(app.insightsRevision.value, initialInsights + n);
    expect(NutritionDb.revision.value, initialFood + n);
  }

  Future<void> failWrites() => db.execute(
    "CREATE TRIGGER synthetic_fail_session BEFORE INSERT ON sessions BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
  );

  test(
    'manual save and retime publish once, failed writes never publish',
    () async {
      final start =
          DateTime.now()
              .subtract(const Duration(days: 5))
              .millisecondsSinceEpoch ~/
          1000;
      await failWrites();
      await expectLater(
        repo.logManualWorkout(
          startTs: start,
          endTs: start + 1800,
          type: 'yoga',
        ),
        throwsA(anything),
      );
      published(0);
      await db.execute('DROP TRIGGER synthetic_fail_session');
      final saved = await repo.logManualWorkout(
        startTs: start,
        endTs: start + 1800,
        type: 'yoga',
      );
      final id = saved['workout_id'] as String;
      expect((await LocalDb.session(id))?['end_ts'], start + 1800);
      published(1);
      await failWrites();
      await expectLater(
        repo.setWorkoutWindow(id, startTs: start, endTs: start + 2400),
        throwsA(anything),
      );
      expect((await LocalDb.session(id))?['end_ts'], start + 1800);
      published(1);
      await db.execute('DROP TRIGGER synthetic_fail_session');
      await repo.setWorkoutWindow(id, startTs: start, endTs: start + 2400);
      expect((await LocalDb.session(id))?['end_ts'], start + 2400);
      published(2);
    },
  );
  test('coach save uses the same post-commit signal', () async {
    final args = <String, dynamic>{
      'date': dayLabelOf(DateTime.now().subtract(const Duration(days: 7))),
      'start_time': '08:00',
      'duration_min': 30,
      'type': 'yoga',
    };
    await failWrites();
    await expectLater(
      CoachActions.addCompletedWorkout(repo, args),
      throwsA(isA<CoachActionError>()),
    );
    published(0);
    await db.execute('DROP TRIGGER synthetic_fail_session');
    await CoachActions.addCompletedWorkout(repo, args);
    expect(await db.query('sessions'), hasLength(1));
    published(1);
  });
}
