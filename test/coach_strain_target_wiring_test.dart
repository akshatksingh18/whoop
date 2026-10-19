// The strain target reaches the Today row, the Coach screen and the home widget.
//
// There were TWO strain targets with different key names, and only one was ever
// produced. The cross-day pipeline writes `strain_coach` ({target_min,
// target_max, band, rationale}) into the insights map, which the Insights
// Strain Coach card reads. `CoachData` — the model behind Today's "Today's
// plan" chip, the Coach screen's target tile and the home-screen widget — reads
// `coach.strain_target` ({value, low, high, rationale}) instead, and NOTHING in
// the app ever wrote a `coach` key: `sub('coach')` in payloads.dart was the only
// occurrence of that key in the whole codebase. The three surfaces silently
// rendered nothing, and the test fixture that "covered" them supplied a shape
// production never emitted.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

/// A cross-day map shaped exactly like `crossDayPipeline` emits.
Map<String, dynamic> crossDayWith(Object? strainCoachValue) => {
  'strain_coach': {
    'value': strainCoachValue,
    'confidence': 0.6,
    'tier': 'ESTIMATE',
    'inputs_used': const ['recovery', 'load'],
  },
};

void main() {
  group('coachToday — cross-day strain_coach → coach.strain_target', () {
    test('maps the band onto the value/low/high shape CoachData reads', () {
      final coach = coachToday(
        crossDayWith({
          'target_min': 9.0,
          'target_max': 14.0,
          'band': 'maintain',
          'rationale': 'Target shaped by recovery and recent load.',
        }),
      );

      final t = coach?['strain_target'] as Map<String, dynamic>?;
      expect(t, isNotNull);
      expect(t!['low'], closeTo(9.0, 1e-9));
      expect(t['high'], closeTo(14.0, 1e-9));
      // The headline number is the centre of the aim band.
      expect(t['value'], closeTo(11.5, 1e-9));
      expect(t['rationale'], 'Target shaped by recovery and recent load.');
    });

    test('an absent target produces no coach map rather than a fake one', () {
      // `strainTarget` abstains until there is a recovery value today. An
      // abstaining metric must not surface as a 0–0 aim band.
      expect(coachToday(crossDayWith(null)), isNull);
      expect(coachToday(const {}), isNull);
      expect(coachToday(null), isNull);
    });

    test('a malformed band is dropped, not half-rendered', () {
      expect(coachToday(crossDayWith({'band': 'maintain'})), isNull);
      expect(coachToday(crossDayWith({'target_min': 9.0})), isNull);
    });
  });
}
