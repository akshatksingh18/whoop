// Build 95 (Q4): miles everywhere a run or walk is measured — splits re-cut
// per mile, spoken updates per mile, and kilometre splits labelled as recorded
// when a session cannot be re-cut.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gps/motion_window.dart';
import 'package:openstrap_edge/gps/run_analysis.dart';
import 'package:openstrap_edge/gps/run_voice.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';

void main() {
  test('the voice speaks each mile, with that mile\'s time', () {
    final v = KmVoice(miles: true);
    expect(v.update(1.0, 300, speak: false), isNull, reason: 'not a mile yet');
    final line = v.update(1.7, 570, speak: false);
    expect(line, startsWith('1 mile. Last mile '));
    expect(v.spokenKm, 1);
    expect(kmCue(3, 570, miles: true), '3 miles. Last mile 9 minutes 30.');
    expect(kmCue(1, 400), '1 kilometre. Last kilometre 6 minutes 40.');
  });

  test('a session keeps the unit it started with across a restore', () {
    final v = KmVoice(miles: true)..update(0.5, 180, speak: false);
    final back = KmVoice.restore(v.snapshot(), spoken: 0);
    expect(back.miles, isTrue);
    final km = KmVoice.restore({'km': 0.5, 'seconds': 180, 'crossing': 0});
    expect(km.miles, isFalse, reason: 'an older run was spoken in km');
  });

  test('phone-motion splits can be cut every mile', () {
    // Ten minutes at 200 m a minute: 2 km, about 1.24 miles.
    final w = MotionWindow(
      DateTime(2026, 10, 19, 7),
      60,
      List.filled(10, 160),
      List<double?>.filled(10, 200.0),
    );
    final mi = w.splits(unitMeters: 1609.344);
    expect(mi.first.km, 1);
    expect(mi.first.sec, closeTo(483, 1));
    expect(mi.last.km, closeTo((2000 - 1609.344) / 1609.344, 1e-6));
    expect(w.splits().map((s) => s.km), [1, 1]);
  });

  test('miles are shown when the session has them; else km, said so', () {
    final a = activityByName('Running')!;
    final km = [const KmSplit(1, 300), const KmSplit(1, 310)];
    final withMiles = ActivityResult(
      a,
      start: DateTime(2026, 10, 19, 7),
      duration: const Duration(minutes: 10),
      splits: km,
      mileSplits: const [KmSplit(1, 490)],
    );
    final miles = UnitsController.withUnits(distance: 'mi');
    expect(shownSplits(withMiles, miles).unit, 'mi');
    expect(shownSplits(withMiles, miles).asRecorded, isFalse);
    final older = withMiles.copyWith(mileSplits: const []);
    final shown = shownSplits(older, miles);
    expect(shown.unit, 'km');
    expect(shown.asRecorded, isTrue);
    expect(shownSplits(withMiles, UnitsController.withUnits()).unit, 'km');
  });

  test('a mile is a best effort, between 1K and 5K', () {
    final labels = [for (final (l, _) in kBestEffortDistances) l];
    expect(labels, ['1K', '1 mile', '5K', '10K', 'Half marathon']);
  });
}
