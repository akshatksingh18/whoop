// CIRCADIAN wiring — the nonparametric battery (IS/IV/RA/L5/M10) and the 24 h
// cosinor now run in the cross-day rollup over the per-day `hourly_hr` profile.
//
// The things that can go wrong here are all HONESTY failures, not arithmetic
// ones, so that is what this file pins:
//   * a number from too few days (the whole point of the minimum-days gate),
//   * a number from an INCOMPLETE day (an imputed hour is exactly the smooth,
//     regular signal IS is designed to reward — imputation manufactures rhythm
//     strength out of missing data),
//   * a number stitched across a multi-day gap (IV differences successive
//     epochs; a jump across a gap is not an hour-to-hour transition),
//   * a note that does not say what the metric was actually computed FROM.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';

/// A physiologically-shaped 24 h HR profile: nocturnal trough, daytime plateau.
/// [phaseShiftH] moves the whole rhythm later, [flat] removes it entirely.
List<double?> _profile({int phaseShiftH = 0, bool flat = false}) => [
      for (var h = 0; h < 24; h++)
        flat
            ? 60.0
            : () {
                final local = (h - phaseShiftH + 24) % 24;
                // Trough 02:00-06:00, peak ~14:00-18:00.
                return local >= 1 && local <= 6 ? 50.0 : 75.0;
              }(),
    ];

String _date(int i) {
  final d = DateTime.utc(2024, 5, 1).add(Duration(days: i));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Oldest-first day series carrying only what the circadian block reads.
List<Map<String, dynamic>> _days(
  int n, {
  List<double?>? Function(int i)? profileFor,
  Set<int> skipDates = const {},
}) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < n; i++) {
    if (skipDates.contains(i)) continue;
    out.add({
      'date': _date(i),
      'hourly_hr': profileFor?.call(i) ?? _profile(),
    });
  }
  return out;
}

Map<String, dynamic> _npOf(Map<String, dynamic> b) =>
    (b['circadian_rhythm'] as Map).cast<String, dynamic>();
Map<String, dynamic> _cosOf(Map<String, dynamic> b) =>
    (b['circadian_cosinor'] as Map).cast<String, dynamic>();
Map<String, dynamic> _covOf(Map<String, dynamic> b) =>
    (b['circadian_coverage'] as Map).cast<String, dynamic>();

void main() {
  const profile = <String, dynamic>{'age': 34, 'sex': 'male', 'weight_kg': 75};

  group('circadian minimum-days gate', () {
    test('three days: nonparametric abstains with a need_baseline note', () {
      final b = buildCrossDayBundle(_days(3), profile);
      final np = _npOf(b);
      expect(np['value'], '—');
      expect(np['confidence'], 0);
      expect(
        np['note'],
        'need_baseline:have=3,need=$kCircadianNpMinDays',
        reason: 'the machine-readable form is what the UI parses to render '
            '"N more nights" — it must be exact, not prose',
      );
    });

    test('three days: cosinor is AT its own minimum and computes', () {
      // The two families have different minimums on purpose, and the gate is
      // per-family: three days is enough for a phase estimate, not for IS.
      final cos = _cosOf(buildCrossDayBundle(_days(3), profile));
      expect(cos['value'], isA<Map>());
      expect(kCircadianCosinorMinDays, 3);
    });

    test('two days: BOTH abstain', () {
      final b = buildCrossDayBundle(_days(2), profile);
      expect(_npOf(b)['value'], '—');
      expect(_cosOf(b)['value'], '—');
      expect(
        _cosOf(b)['note'],
        'need_baseline:have=2,need=$kCircadianCosinorMinDays',
      );
    });

    test('no hourly_hr at all: abstains at have=0, never throws', () {
      final days = [
        for (var i = 0; i < 30; i++) {'date': _date(i)},
      ];
      final b = buildCrossDayBundle(days, profile);
      expect(_npOf(b)['note'], 'need_baseline:have=0,need=$kCircadianNpMinDays');
      expect(_covOf(b)['days_used'], 0);
    });
  });

  group('circadian computes on a full week', () {
    test('a clean 10-day rhythm yields IS/IV/RA/L5/M10 and a cosinor fit', () {
      final b = buildCrossDayBundle(_days(10), profile);
      final np = _npOf(b);
      final v = (np['value'] as Map).cast<String, dynamic>();

      expect(np['confidence'], greaterThan(0));
      expect(np['tier'], 'HIGH');
      // A perfectly reproduced daily profile is maximally stable and minimally
      // fragmented — the two ends of the battery, in the right directions.
      expect(v['IS'] as num, greaterThan(0.9));
      expect(v['IV'] as num, lessThan(0.5));
      expect(v['RA'] as num, greaterThan(0));
      expect(v['M10'] as num, greaterThan(v['L5'] as num));

      final cos = (_cosOf(b)['value'] as Map).cast<String, dynamic>();
      expect(cos['mesor'] as num, greaterThan(50));
      expect(cos['amplitude'] as num, greaterThan(0));
      expect((cos['acrophase_hours'] as num) >= 0, isTrue);
      expect(_covOf(b)['days_used'], 10);
    });

    test('a flat series abstains rather than reporting a rhythm', () {
      final b = buildCrossDayBundle(
        _days(10, profileFor: (_) => _profile(flat: true)),
        profile,
      );
      // No variance ⇒ the battery has nothing to describe. It says so instead
      // of dividing by zero into a confident-looking number.
      expect(_npOf(b)['value'], '—');
      expect(_npOf(b)['note'], contains('variance'));
    });

    test('the note discloses that the input is HR, not accelerometry', () {
      final np = _npOf(buildCrossDayBundle(_days(10), profile));
      expect(
        np['note'],
        contains('HEART-RATE'),
        reason: 'M10/L5 here are highest/lowest-HR windows, not step counts; a '
            'reader who assumes actigraphy would misread the units',
      );
    });
  });

  group('day admission', () {
    test('a day with ANY uncovered hour is excluded, not filled', () {
      // Ten days, but every one of them is missing hour 3.
      final holed = _profile()..[3] = null;
      final b = buildCrossDayBundle(
        _days(10, profileFor: (_) => holed),
        profile,
      );
      expect(_covOf(b)['days_used'], 0);
      expect(_npOf(b)['note'], 'need_baseline:have=0,need=$kCircadianNpMinDays');
    });

    test('the LONGEST consecutive run is used', () {
      // 12 days with day 5 incomplete: two runs, 0-4 (five days) and 6-11 (six
      // days). The longer one wins — and either way it must abstain rather than
      // silently stitching 11 days across the hole.
      final b = buildCrossDayBundle(
        _days(12, profileFor: (i) => i == 5 ? (_profile()..[3] = null) : null),
        profile,
      );
      expect(_covOf(b)['days_used'], 6);
      expect(_npOf(b)['note'], 'need_baseline:have=6,need=$kCircadianNpMinDays');
    });

    test('RD-03: a trailing incomplete day cannot zero the block', () {
      // THE BUG THIS FILE EXISTS TO CATCH NOW. `days` always ends with TODAY —
      // flagged `unsettled`, never dropped — and today cannot have 24 covered
      // local hours until midnight. Reading the run AFTER the loop meant that
      // last day cleared it every time, so IS/IV and the cosinor were absent
      // permanently while the note said `have=0` about a corpus with 88–97 %
      // daily coverage. On the real gen4 export the shipped code found have=0
      // where the data holds a five-day run.
      final b = buildCrossDayBundle(
        _days(11, profileFor: (i) => i == 10 ? (_profile()..[3] = null) : null),
        profile,
      );
      expect(_covOf(b)['days_used'], 10);
      expect(_covOf(b)['first_day'], _date(0));
      expect(_covOf(b)['last_day'], _date(9));
      expect(_npOf(b)['value'], isA<Map>());
      expect(_cosOf(b)['value'], isA<Map>());
    });

    test('a CALENDAR gap breaks the run even when both sides are complete', () {
      // Days 0-3 present, 4-5 missing entirely (never derived), 6-11 present.
      final b = buildCrossDayBundle(
        _days(12, skipDates: {4, 5}),
        profile,
      );
      expect(
        _covOf(b)['days_used'],
        6,
        reason: 'IV differences successive epochs; a 23:00 -> 00:00 step across '
            'a two-day hole is not an hour-to-hour transition',
      );
      expect(_covOf(b)['first_day'], _date(6));
      expect(_covOf(b)['last_day'], _date(11));
    });
  });

  test('circadian never throws the whole rollup', () {
    // Junk in every position the block reads.
    final days = [
      {'date': _date(0), 'hourly_hr': 'not a list'},
      {'date': null, 'hourly_hr': const [1, 2, 3]},
      {'date': _date(2), 'hourly_hr': const []},
      {'date': _date(3), 'hourly_hr': [for (var i = 0; i < 24; i++) 'x']},
    ];
    final b = buildCrossDayBundle(days, profile);
    expect(_npOf(b)['value'], '—');
    expect(_covOf(b)['days_used'], 0);
  });
}
