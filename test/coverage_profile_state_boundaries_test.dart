// Profile/step-goal state changes: validation precedes publication and failures roll back.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/profile_history.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('profile-state'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const original = {
    'age': 30,
    'height_cm': 170.0,
    'weight_kg': 70.0,
    'sex': 'f',
    'step_goal': 8000,
  };
  for (final (key, value) in <(String, Object)>[
    ('age', 0),
    ('age', 121),
    ('age', 30.5),
    ('height_cm', 29),
    ('height_cm', 281),
    ('weight_kg', .5),
    ('weight_kg', 501),
    ('weight_kg', 'bad'),
    ('weight_kg', double.infinity),
    ('step_goal', 499),
    ('step_goal', 100001),
    ('step_goal', 9000.5),
    ('step_goal', 'bad'),
  ]) {
    test(
      'COV-44 AppState invalid $key $value preserves current profile and goal ledger',
      () async {
        final app = AppState.forTesting()..user = {...original};
        addTearDown(app.dispose);
        final beforeGoal = await CalculationStore.read(StepGoals.key);
        final beforeProfile = await CalculationStore.read(ProfileHistory.key);
        await expectLater(app.updateProfile({key: value}), throwsArgumentError);
        expect(app.user, original);
        expect(await CalculationStore.read(StepGoals.key), beforeGoal);
        expect(await CalculationStore.read(ProfileHistory.key), beforeProfile);
      },
    );
  }
  test(
    'COV-44 AppState step goal changes persist dated anchors before publication',
    () async {
      final app = AppState.forTesting()..user = {...original};
      addTearDown(app.dispose);
      expect((await app.updateProfile({'step_goal': 9000}))['step_goal'], 9000);
      expect(await CalculationStore.read(StepGoals.key), contains('9000'));
      expect(await CalculationStore.read(ProfileHistory.key), isNotNull);
    },
  );
}
