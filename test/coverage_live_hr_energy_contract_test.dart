// The active workout host's Method 2 readout, using the already-approved net
// Keytel/Mifflin calculation. Synthetic profiles/observations; no formula change.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUp(() => app = AppState.forTesting());
  tearDown(() {
    app.activeWorkout = null;
    app.dispose();
  });

  LiveWorkoutState session(Profile profile) =>
      app.activeWorkout = LiveWorkoutState(
        startTime: DateTime(2021, 4, 6, 8),
        targetKcal: 300,
        type: 'cycling',
        profile: profile,
        hrMax: 185,
        restingHr: 55,
      );

  const male = Profile(ageYears: 30, weightKg: 70, heightCm: 175, sex: 'm');
  // Independently evaluate the established published terms. No call to the
  // production pricing helper is used to compute these expected net rates.
  final maleRate =
      (-55.0969 + .6309 * 130 + .1988 * 70 + .2017 * 30) / 4.184 -
      (10 * 70 + 6.25 * 175 - 5 * 30 + 5) / 1440;
  final femaleRate =
      (-20.4022 + .4472 * 130 - .1263 * 70 + .074 * 30) / 4.184 -
      (10 * 70 + 6.25 * 175 - 5 * 30 - 161) / 1440;

  for (final (sex, rate) in [
    ('m', maleRate),
    ('male', maleRate),
    ('f', femaleRate),
    ('female', femaleRate),
    ('other', (maleRate + femaleRate) / 2),
  ]) {
    test(
      'the live host uses the captured $sex profile and rounds net energy once',
      () {
        final w = session(
          Profile(ageYears: 30, weightKg: 70, heightCm: 175, sex: sex),
        );
        w.accrueHr(130);
        w.elapsed = const Duration(seconds: 90);
        expect(app.workoutHrActiveKcal, (rate * 1.0).round());
        // The one observed minute is billed, not the unobserved final half.
        expect(w.perMinuteHrDense(), [130.0]);
        final retained = app.workoutHrActiveKcal;
        app.user = {'age': 65, 'weight_kg': 140, 'height_cm': 150, 'sex': 'f'};
        expect(Profile.fromMap(app.user).isComplete, true);
        expect(app.workoutHrActiveKcal, retained);
        expect(w.profile.weightKg, 70);
        expect(w.profile.ageYears, 30);
      },
    );
  }

  test(
    'missing minutes stay holes and the measured last half-minute is fractional',
    () {
      final w = session(male);
      w.accrueHr(130);
      w.elapsed = const Duration(minutes: 2);
      w.accrueHr(130);
      w.elapsed = const Duration(seconds: 150);
      expect(w.perMinuteHrDense(), [130.0, null, 130.0]);
      expect(app.workoutHrActiveKcal, (maleRate * 1.5).round());
      expect(w.elapsed, const Duration(seconds: 150));
    },
  );

  test(
    'no readings remain unknown while measured low-rate energy can be zero',
    () {
      final w = session(male);
      w.elapsed = const Duration(minutes: 2);
      w.accrueHr(0);
      w.accrueHr(-1);
      expect(app.workoutHrActiveKcal, isNull);
      expect(w.perMinuteHrDense(), isEmpty);
      w.elapsed = Duration.zero;
      w.accrueHr(20);
      w.elapsed = const Duration(minutes: 1);
      expect(app.workoutHrActiveKcal, 0);
      expect(w.perMinuteHrDense(), [20.0]);
    },
  );

  for (final (name, profile) in [
    ('age', const Profile(weightKg: 70, heightCm: 175, sex: 'm')),
    ('weight', const Profile(ageYears: 30, heightCm: 175, sex: 'm')),
    ('height', const Profile(ageYears: 30, weightKg: 70, sex: 'm')),
  ]) {
    test('missing $name cannot be filled from a newer complete profile', () {
      final w = session(profile);
      w.accrueHr(130);
      w.elapsed = const Duration(minutes: 1);
      app.user = {'age': 30, 'weight_kg': 70, 'height_cm': 175, 'sex': 'm'};
      expect(Profile.fromMap(app.user).isComplete, true);
      expect(app.workoutHrActiveKcal, isNull);
      expect(w.perMinuteHrDense(), [130.0]);
    });
  }
}
