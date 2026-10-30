// Recorded movement readers keep the approved headline separate from qualified
// comparisons. These are fixed arithmetic contracts, not new calorie methods.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/activity/run_detail.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  setUpAll(loadAuditFonts);
  final start = DateTime(2021, 4, 6, 12);
  const profile = Profile(weightKg: 70);
  ActivityResult run({bool supported = true, bool weight = true}) =>
      ActivityResult(
        activityByName('Running')!,
        start: start,
        duration: const Duration(minutes: 15),
        calories: 999,
        calculationProfile: weight ? profile : const Profile(),
        mix: (
          runM: 1000,
          walkM: 300,
          climbM: 20,
          runSec: supported ? 240 : 900,
          walkSec: supported ? 240 : 60,
        ),
      );
  testWidgets(
    'recorded run headline ignores a stale stored calorie figure and keeps the qualified comparison separate',
    (t) async {
      final r = run();
      expect(r.calories, 76);
      expect(r.acsmCalories, closeTo(86.8, 1e-9));
      expect(r.movementEstimateCalories, closeTo(86.8, 1e-9));
      await localizedPage(t, RunCaloriesCard(r, profile));
      expect(find.text('76'), findsOneWidget);
      expect(find.text('ACSM'), findsOneWidget);
      expect(find.text('999'), findsNothing);
    },
  );
  testWidgets(
    'unsupported speed refuses a qualified ACSM value while retaining the established headline and labelled estimate',
    (t) async {
      final r = run(supported: false);
      expect(r.calories, 76);
      expect(r.acsmCalories, isNull);
      expect(r.movementEstimateCalories, closeTo(86.8, 1e-9));
      await localizedPage(t, RunCaloriesCard(r, profile));
      expect(find.text('76'), findsOneWidget);
      expect(find.text('Movement estimate'), findsOneWidget);
    },
  );
  testWidgets(
    'a saved run without recorded weight cannot substitute a cached calorie figure',
    (t) async {
      final r = run(weight: false);
      expect(r.calories, isNull);
      expect(r.acsmCalories, isNull);
      expect(r.movementEstimateCalories, isNull);
      await localizedPage(t, RunCaloriesCard(r, const Profile()));
      expect(find.text('999'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('Unavailable'), findsNWidgets(2));
    },
  );
  testWidgets(
    'a saved walk uses counted steps for its headline and distance only for the separate comparison',
    (t) async {
      final r = ActivityResult(
        activityByName('Walking')!,
        start: start,
        duration: const Duration(minutes: 15),
        calories: 999,
        calculationProfile: profile,
        distanceKm: 1,
        movingSec: 900,
        phoneSteps: 1000,
      );
      expect(r.calories, 23);
      expect(r.acsmCalories, closeTo(35, 1e-9));
      expect(r.movementEstimateCalories, closeTo(35, 1e-9));
      await localizedPage(t, RunCaloriesCard(r, profile));
      expect(find.text('23'), findsOneWidget);
      expect(find.text('999'), findsNothing);
    },
  );
}
