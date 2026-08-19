import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/driver_breakdown.dart';

/// The bug this pins: "What charged and drained you" printed two bare words —
/// "hrv", "rhr" — because it read `readiness_glassbox.drivers`, which is
/// ALREADY FILTERED to the inputs that cleared the smallest-worthwhile-change
/// gate. An input sitting inside its usual spread was never in that array, so
/// the screen could not say "and your breathing rate did nothing", which is
/// half of what "what changed" means. It reads `breakdown` now.
void main() {
  // One usable input, one present-but-inside-its-spread, one absent. The
  // shapes come from the real payload: `used`, `weight`,
  // `weighted_contribution`, `past_mdc`, `note` on the breakdown; `value`,
  // `baseline`, `spread`, `delta`, `mdc_multiples` on the baselines block.
  // The wire name is `weighted_contribution` — a test built on `contribution`
  // passes its own fiction and reports every driver as "neither".
  List<Map<String, dynamic>> bd() => [
        {
          'label': 'hrv',
          'used': true,
          'weight': 0.40,
          'weighted_contribution': -6.2,
          'past_mdc': true,
        },
        {
          'label': 'rhr',
          'used': true,
          'weight': 0.30,
          'weighted_contribution': 3.1,
          'past_mdc': false,
        },
        {
          'label': 'resp',
          'used': false,
          'weight': 0.15,
          'note': 'need_baseline:have=2,need=7',
        },
      ];

  test('an input that did nothing still gets a row', () {
    final f = driverFacts(breakdown: bd());
    // Three in, three out. The old path would have dropped `resp` entirely.
    expect(f.length, 3);
    expect(f.map((e) => e.key), containsAll(<String>['hrv', 'rhr', 'resp']));
  });

  test('the unusable input carries its own reason, not a guess', () {
    final f = driverFacts(breakdown: bd());
    final resp = f.firstWhere((e) => e.key == 'resp');
    expect(resp.used, isFalse);
    expect(resp.note, 'need_baseline:have=2,need=7');
  });

  test('weight is the share actually carried, not the catalogue figure', () {
    // Usable weight is 0.40 + 0.30 = 0.70, so HRV's catalogue 40 % really
    // carried 57 %. Printing 40 % would disclose a weight that was not used.
    final f = driverFacts(breakdown: bd());
    final hrv = f.firstWhere((e) => e.key == 'hrv');
    expect(hrv.weightShare, closeTo(0.40 / 0.70, 1e-9));
  });

  test('right and wrong are split on the sign, never inferred', () {
    final s = splitDrivers(driverFacts(breakdown: bd()));
    expect(s.helped.map((e) => e.key), ['rhr']);
    expect(s.held.map((e) => e.key), ['hrv']);
    // Unusable is neither — it did not help and it did not hold you back.
    expect(s.neither.map((e) => e.key), ['resp']);
  });

  test('a zero contribution is neither, not a tiny win', () {
    final s = splitDrivers(driverFacts(breakdown: [
      {'label': 'hrv', 'used': true, 'weight': 1.0, 'weighted_contribution': 0.0},
    ]));
    expect(s.helped, isEmpty);
    expect(s.held, isEmpty);
    expect(s.neither.length, 1);
  });

  test('each side is ordered by how much it moved the score', () {
    final s = splitDrivers(driverFacts(breakdown: [
      {'label': 'hrv', 'used': true, 'weight': .5, 'weighted_contribution': -2.0},
      {'label': 'rhr', 'used': true, 'weight': .5, 'weighted_contribution': -9.0},
    ]));
    expect(s.held.map((e) => e.key), ['rhr', 'hrv']);
  });

  test('no breakdown at all is an empty list, not a fabricated row', () {
    expect(driverFacts(breakdown: const []), isEmpty);
  });

  test('an input the map has never heard of still gets a row', () {
    // The pipeline is allowed to grow a fifth input without this screen
    // silently dropping it — label, weight and contribution are all in the
    // breakdown itself. It simply has no baseline block and no chart.
    final f = driverFacts(breakdown: [
      {'label': 'newthing', 'used': true, 'weight': 1.0, 'weighted_contribution': 4.0},
    ]);
    expect(f.single.key, 'newthing');
    expect(f.single.value, isNull);
    // The series is DENSE — one slot per day, null where nothing was measured.
    // An unknown key has no chart, so every slot is null; it is not an empty
    // list, and a screen drawing it must treat null as absent rather than 0.
    expect(f.single.series.length, kDriverChartDays);
    expect(f.single.series.every((v) => v == null), isTrue);
  });

  test('a missing baselines block leaves the numbers absent, never zero', () {
    final f = driverFacts(breakdown: bd(), baselines: null);
    for (final d in f) {
      expect(d.value, isNull);
      expect(d.usual, isNull);
      expect(d.delta, isNull);
      expect(d.mdcMultiples, isNull);
    }
  });

  test('the spread gate is read from the wire, not re-derived', () {
    final f = driverFacts(breakdown: bd());
    expect(f.firstWhere((e) => e.key == 'hrv').beyondUsualSpread, isTrue);
    expect(f.firstWhere((e) => e.key == 'rhr').beyondUsualSpread, isFalse);
  });
}
