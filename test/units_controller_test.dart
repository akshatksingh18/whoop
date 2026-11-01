// UnitsController pace formatting — regression coverage for a real user
// report: a near-zero GPS distance divided into real elapsed time produced
// an absurd "189:xx" style pace.
//
// The honest answer is NULL, not '—'. A formatter cannot know why a value is
// missing, and a bare dash rendered into a stat slot is a defect on its own —
// the callers now drop the stat instead of drawing a placeholder.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UnitsController pace sanity ceiling', () {
    test('formatPace answers null for an absurdly slow pace, not the raw '
        'number', () {
      // 1000 min/km — the exact class of number the bug produced.
      expect(UnitsController.formatPace(1000 * 60), isNull);
    });

    test('formatPace still shows a real, plausible pace normally', () {
      expect(UnitsController.formatPace(5 * 60 + 30), '5:30');
    });

    test('pace() returns null (never "— /km") for a near-zero distance '
        'over real elapsed time — the exact bed-jitter scenario', () {
      final u = UnitsController.seed(UnitSystem.metric);
      // 1 metre over 60 seconds — GPS noise, not a real 60 min/km pace.
      expect(u.pace(1, 60), isNull);
    });

    test('pace() returns a normal formatted pace for real distance/time', () {
      final u = UnitsController.seed(UnitSystem.metric);
      // 1 km in 5:30 → "5:30 /km".
      expect(u.pace(1000, 5 * 60 + 30), '5:30 /km');
    });

    test('paceFromSpeed() returns null consistently, never "— /km"', () {
      final u = UnitsController.seed(UnitSystem.metric);
      expect(u.paceFromSpeed(null), isNull);
      expect(u.paceFromSpeed(0), isNull);
    });
  });

  group('imperial', () {
    final u = UnitsController.seed(UnitSystem.imperial);

    test('distance converts and labels in miles', () {
      // 5 km = 3.107 mi.
      expect(u.distance(5000), '3.11 mi');
      expect(u.distanceUnit, 'mi');
    });

    test('pace is per mile, not per km', () {
      // 5:00/km over 5 km is 8:03/mi (5 min × 1.609344).
      expect(u.pace(5000, 25 * 60), '8:03 /mi');
    });

    test('speed reads mph', () {
      // 10 m/s = 22.4 mph.
      expect(u.speed(10), '22.4 mph');
    });

    test('metric is unchanged', () {
      final m = UnitsController.seed(UnitSystem.metric);
      expect(m.distance(5000), '5.00 km');
      expect(m.pace(5000, 25 * 60), '5:00 /km');
      expect(m.speed(10), '36.0 km/h');
    });
  });

  // Build 95 (option A): weight, distance and height are separate choices.
  group('separate choices', () {
    test('a Body choice already made wins over the old switch', () {
      final u = UnitsController.fromPrefs(weight: 'lb', legacySystem: 'metric');
      expect(u.weightUnit, 'lb');
      expect(u.distanceUnit, 'km');
      expect(u.heightUnit, HeightUnit.cm);
    });

    test('with no Body choice, the old switch decides every measure', () {
      final u = UnitsController.fromPrefs(legacySystem: 'imperial');
      expect(u.weightUnit, 'lb');
      expect(u.distanceUnit, 'mi');
      expect(u.heightUnit, HeightUnit.ftIn);
      final m = UnitsController.fromPrefs();
      expect(m.weightUnit, 'kg');
      expect(m.distanceUnit, 'km');
      expect(m.heightUnit, HeightUnit.cm);
    });

    test('miles leave weight and height alone', () {
      final u = UnitsController.withUnits(distance: 'mi');
      expect(u.distance(1609.344), '1.00 mi');
      expect(u.weight(70), '70 kg');
      expect(u.height(180), '180 cm');
    });

    test('pounds leave distance alone, and convert both ways', () {
      final u = UnitsController.withUnits(weight: 'lb');
      expect(u.weight(70), '154 lb');
      expect(u.weightToKg('154.32'), closeTo(70, 0.01));
      expect(u.distance(5000), '5.00 km');
    });

    test('bootstrap writes every choice down, so the old switch is read once',
        () async {
      SharedPreferences.setMockInitialValues({'units_system': 'imperial'});
      final u = await UnitsController.bootstrap();
      expect(u.weightUnit, 'lb');
      final p = await SharedPreferences.getInstance();
      expect(p.getString(UnitsController.kWeightPref), 'lb');
      expect(p.getString(UnitsController.kDistancePref), 'mi');
      expect(p.getString(UnitsController.kHeightPref), 'ftIn');
      await u.setDistanceUnit('km');
      expect(p.getString(UnitsController.kDistancePref), 'km');
      expect(u.weightUnit, 'lb', reason: 'one measure never moves another');
    });
  });
}
