// The button verb, and the record it reads.
//
// The whole point of the stored flag is that the store cannot be asked: iOS
// never reveals whether a READ was granted, so "have we imported before" has
// to be our own answer. These check that the answer round-trips and that the
// word on the button follows it.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/health/health_import_state.dart';
import 'package:openstrap_edge/health/health_workout_import.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('never imported reads as null, and the button says Import', () async {
    expect(await lastImportAt(HealthImport.workouts), isNull);
    expect(importLabel(null), startsWith('Import from '));
  });

  test('a recorded import round-trips, and the button says Refresh', () async {
    final at = DateTime(2026, 8, 16, 7, 12);
    await markImported(HealthImport.workouts, now: at);
    final read = await lastImportAt(HealthImport.workouts);
    // Stored to the second, so equality is on the second and not on the
    // millisecond the DateTime happens to carry.
    expect(read?.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch - at.millisecond);
    expect(importLabel(read), startsWith('Refresh from '));
  });

  test('the two imports are independent', () async {
    await markImported(HealthImport.profile);
    // Reading your weight is not reading your workouts, and one button must
    // never claim the other's consent.
    expect(await lastImportAt(HealthImport.profile), isNotNull);
    expect(await lastImportAt(HealthImport.workouts), isNull);
  });

  group('the store\'s own word for the activity', () {
    test('is title-cased and de-underscored', () {
      expect(importedWorkoutTitle('RUNNING'), 'Running');
      expect(importedWorkoutTitle('HIGH_INTENSITY_INTERVAL_TRAINING'),
          'High Intensity Interval Training');
    });

    test('never renders as blank', () {
      // A type this build has never heard of still has to print something —
      // an empty row is indistinguishable from a rendering bug.
      expect(importedWorkoutTitle(null), 'Workout');
      expect(importedWorkoutTitle('  '), 'Workout');
      expect(importedWorkoutTitle(42), 'Workout');
    });
  });
}
