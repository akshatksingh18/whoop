// Existing live energy methods must abstain without discarding observations.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/state/app_state.dart';

void main() {
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  LiveWorkoutState state({double rhr = 60, double max = 190}) =>
      LiveWorkoutState(
        startTime: DateTime.utc(2021, 4, 6, 12),
        targetKcal: 300,
        profile: profile,
        hrMax: max,
        restingHr: rhr,
      );
  for (final rhr in [0.0, -1.0, double.nan, double.infinity, 190.0, 220.0]) {
    test(
      'COV-60 invalid resting anchor $rhr abstains and accepts a later real anchor',
      () {
        final live = state(rhr: rhr);
        live.accrueHr(120);
        expect(live.caloriesOrNull, isNull);
        expect(live.meanHr, 120);
        expect(live.perMinuteHrDense(), [120.0]);
        live.restingHr = 60;
        live.elapsed = const Duration(seconds: 2);
        live.accrueHr(120);
        expect(live.caloriesOrNull, isNotNull);
        expect(live.calories, greaterThan(0));
        expect(live.meanHr, 120);
        expect(live.perMinuteHrDense(), [120.0]);
        expect(live.hasSamplesAfter(const Duration(seconds: 1)), true);
      },
    );
  }
  for (final max in [0.0, -1.0, double.nan, double.infinity, 60.0]) {
    test(
      'COV-60 invalid maximum anchor $max cannot manufacture measured calories',
      () {
        final live = state(max: max);
        live.accrueHr(120);
        live.elapsed = const Duration(seconds: 2);
        live.accrueHr(120);
        expect(live.caloriesOrNull, isNull);
        expect(live.meanHr, 120);
        expect(live.perMinuteHrDense(), [120.0]);
        expect(live.hasSamplesAfter(const Duration(seconds: 1)), true);
      },
    );
  }
  for (final end in [0, 10, 20]) {
    test(
      'COV-60 end at ${end}s excludes all later observations without billing unknown time',
      () {
        final live = state()..elapsed = const Duration(seconds: 20);
        live.accrueHr(120);
        live.elapsed = const Duration(seconds: 21);
        live.accrueHr(120);
        expect(live.caloriesOrNull, isNotNull);
        final before = live.calories;
        final bounded = live.boundedAt(Duration(seconds: end), (_) => 1);
        expect(bounded.elapsed, Duration(seconds: end));
        expect(bounded.caloriesOrNull, isNull);
        expect(bounded.meanHr, isNull);
        expect(bounded.perMinuteHrDense(), isEmpty);
        expect(bounded.hasSamplesAfter(Duration.zero), false);
        expect(live.calories, before);
        expect(live.perMinuteHrDense(), [120.0]);
        expect(live.hasSamplesAfter(const Duration(seconds: 20)), true);
      },
    );
  }
}
