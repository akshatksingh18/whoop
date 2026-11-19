import 'package:flutter/material.dart';
import 'package:whoop_companion/ui2/energy_comparison.dart';
import 'package:whoop_companion/ui2/theme.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/run_detail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/day_upkeep.dart';
import 'package:whoop_companion/data/nutrition_store.dart';

List<({String date, double kg})> weights(int count, double slope) => [
  for (var i = 0; i < count; i++)
    (
      date: DateTime.utc(2025, 1, i + 1).toIso8601String().substring(0, 10),
      kg: 80 + slope * i,
    ),
];

void main() {
  const profile = Profile(ageYears: 35, sex: 'm', weightKg: 70, heightCm: 175);
  test(
    'approved METs retain net pricing and functional stays labelled an estimate',
    () {
      expect(conservativeMet('bodyweight', 7), 3.0);
      expect(conservativeMet('calisthenics', 7), 3.8);
      expect(conservativeMet('weight_training', 7), 3.5);
      expect(
        sessionActiveKcal(
          p: profile,
          type: 'bodyweight',
          minutes: 60,
          meanHr: 180,
        ),
        140,
      );
      expect(workoutEnergyMethodLabel('functional'), contains('estimate'));
    },
  );
  test(
    'lifting stays beside maintenance while runs and walking remain inside it',
    () {
      const run = (kcal: 200.0, steps: 2000, count: 1, km: 3.0);
      const before = DayUpkeep(profile, steps: 8000, runs: run, eaten: 2000);
      const after = DayUpkeep(
        profile,
        steps: 8000,
        runs: run,
        eaten: 2000,
        lifting: (kcal: 500.0, sessions: 1, approximate: false),
      );
      expect(after.parts, before.parts);
      expect(after.parts!.run, 200);
      expect(after.parts!.steps, greaterThan(0));
      expect(after.lifting!.kcal, 500);
    },
  );
  test('ACSM qualifies the documented walking and running speed domains', () {
    expect(
      acsmActiveKcal(
        runMeters: 0,
        walkMeters: 3000,
        walkMovingSeconds: 3600,
        weightKg: 70,
      ),
      closeTo(105, 1e-9),
    );
    expect(
      acsmActiveKcal(runMeters: 5000, runMovingSeconds: 1800, weightKg: 70),
      closeTo(350, 1e-9),
    );
    expect(
      acsmActiveKcal(
        runMeters: 0,
        walkMeters: 3000,
        walkMovingSeconds: 1200,
        weightKg: 70,
      ),
      isNull,
    );
    expect(
      acsmActiveKcal(runMeters: 3000, runMovingSeconds: 3600, weightKg: 70),
      isNull,
    );
    expect(acsmActiveKcal(runMeters: 3000, weightKg: 70), isNull);
    expect(
      movementEquationEstimateKcal(runMeters: 3000, weightKg: 70),
      closeTo(210, 1e-9),
    );
  });
  test(
    'session detail retains an estimate without assigning a supported method',
    () {
      final walk = ActivityResult(
        allActivities.firstWhere((a) => a.typeKey == 'walking'),
        start: DateTime(2025, 1, 1),
        duration: const Duration(hours: 1),
        calculationProfile: profile,
        distanceKm: 3,
      );
      expect(walk.acsmCalories, isNull);
      expect(walk.movementEstimateCalories, closeTo(105, 1e-9));
      expect(walk.copyWith(movingSec: 3600).acsmCalories, closeTo(105, 1e-9));
    },
  );
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets('energy methods and full labels fit at ${scale}x', (t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: EnergyComparison(
                    budget: 12345,
                    acsm: 15432,
                    budgetParts: [('Resting energy all day', 1900)],
                    acsmParts: [('Walking distance estimate', 400)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Movement estimate'), findsOneWidget);
      expect(find.text('Walking distance estimate'), findsOneWidget);
      expect(t.takeException(), isNull);
      // Compile the real finished-session consumer alongside the shared view.
      expect(RunCaloriesCard, isNotNull);
    });
  }
  test(
    'short losing and gaining windows include the approved conversion range',
    () {
      for (final slope in [-.05, .05]) {
        final m = measuredMaintenance(
          weights(28, slope),
          List.filled(27, 2200.0),
        )!;
        expect(m.shortWindow, true);
        expect(m.kcal, closeTo(2200 - slope * 7700, 1e-6));
        final expected = [2200 - slope * 4858, 2200 - slope * 7700]..sort();
        expect(m.displayRange.low, closeTo(expected.first, 1e-6));
        expect(m.displayRange.high, closeTo(expected.last, 1e-6));
        expect(m.shown, true);
      }
    },
  );
  test(
    'six weeks means 42 elapsed days; longer estimates retain their old interval',
    () {
      final short = measuredMaintenance(
        weights(42, -.02),
        List.filled(41, 2200.0),
      )!;
      final full = measuredMaintenance(
        weights(43, -.02),
        List.filled(42, 2200.0),
      )!;
      expect(short.shortWindow, true);
      expect(full.shortWindow, false);
      expect(full.displayRange, (low: full.low, high: full.high));
    },
  );
}
