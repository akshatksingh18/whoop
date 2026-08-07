// HONESTY REGRESSION — the strain bonus against tonight's sleep need.
//
// `sleepNeed` adds a strain bonus of `(strain/21) * 45 min` on top of baseline
// need + debt. Today's strain was read with `_lastNum`, which walks BACKWARD
// through the oldest-first day records and returns the last non-null value, so
// on any day where today's strain compute abstained the bonus was built from an
// EARLIER day's strain. That is imputation (AGENTS §3.3, the most-violated rule
// in the repo per §4.1) and it is invisible: the substituted number lands
// inside `need_sec` with nothing surfacing it.
//
// The direction here is the OPPOSITE of the nap bug pinned in
// nap_credit_test.dart, which is exactly why it needs its own pin. Naps are
// SUBTRACTED, so carrying one forward under-recommends sleep; strain is ADDED,
// so carrying it forward over-recommends. Neither direction is a safety
// margin — a rule that inflates need only when yesterday happened to be harder
// than today is noise, not caution. Both must read TODAY or abstain.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';
import 'package:openstrap_edge/ui/insights/coach_cards.dart';

/// Minimal oldest-first day series with the fields sleep need actually reads.
///
/// Every record EXCEPT today's carries a heavy strain (18 of 21). Today's is
/// caller-controlled, so `strainToday: null` models the real case where today's
/// strain compute abstained.
///
/// [todayDerived] false models the common real case where today has no derived
/// row yet, so the most recent record in the list is YESTERDAY — and that row
/// carries the heavy strain, so a positional `days.last` read would pick it up.
/// [weekdayTstMin] / [freeTstMin] split Mon–Fri from Sat/Sun so a test can push
/// baseline need + debt up against `sleepNeed`'s 11 h ceiling. Equal by default,
/// which yields zero debt and a 7.5 h baseline — comfortably mid-band.
List<Map<String, dynamic>> _days(
  int n, {
  double? strainToday,
  bool todayDerived = true,
  int weekdayTstMin = 450,
  int freeTstMin = 450,
}) {
  final out = <Map<String, dynamic>>[];
  var dt = DateTime(2024, 1, 1);
  for (var i = 0; i < n; i++) {
    final last = i == n - 1;
    final isToday = last && todayDerived;
    final isFree =
        dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
    out.add({
      // Stamped by _refreshCrossDayInputArtifact for today's row only.
      if (isToday) 'is_today': true,
      'date': '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}',
      'rhr': 55.0,
      'rmssd': 45.0,
      'readiness': 70.0,
      'onset_sec': 23 * 3600,
      'wake_sec': 31 * 3600,
      'tst_min': isFree ? freeTstMin : weekdayTstMin,
      // Every record that is not today reports heavy strain.
      if (!isToday) 'strain': 18.0,
      if (isToday && strainToday != null) 'strain': strainToday,
      // No nap_min anywhere: the nap path is pinned in nap_credit_test.dart and
      // is held constant here so `need_sec` moves only with strain.
    });
    dt = dt.add(const Duration(days: 1));
  }
  return out;
}

double _needSec(Map<String, dynamic> bundle) {
  final coach = bundle['sleep_coach'] as Map;
  final need = (coach['need'] as Map)['value'] as Map;
  return (need['need_sec'] as num).toDouble();
}

Object? _strainBonus(Map<String, dynamic> bundle) =>
    ((bundle['sleep_coach'] as Map)['strain_bonus_min']);

bool _hasStrainBonusKey(Map<String, dynamic> bundle) =>
    (bundle['sleep_coach'] as Map).containsKey('strain_bonus_min');

/// The bonus `sleepNeed` adds for a given strain: (strain/21) * 45 min.
double _bonusSec(double strain) => (strain / 21.0) * 45.0 * 60.0;

void main() {
  const profile = <String, dynamic>{};

  group('sleep need — the strain bonus is TODAY-scoped', () {
    test("a day with no strain reading is NOT given yesterday's bonus", () {
      // Today abstained; the 6 days before it each report a strain of 18.
      final noReading = buildCrossDayBundle(_days(7), profile);
      // Same series, but today explicitly reports zero strain.
      final explicitZero =
          buildCrossDayBundle(_days(7, strainToday: 0), profile);

      expect(
        _needSec(noReading),
        _needSec(explicitZero),
        reason: 'an absent strain reading must add nothing — reaching back a '
            'day for a number is imputation, and it inflates tonight\'s '
            'recommendation with a workout the user did not do today',
      );
    });

    test('that assertion can actually see the difference', () {
      // Guard on the test itself: `sleepNeed` clamps to [6 h, 11 h] AFTER
      // adding, so a series that saturated the ceiling would make the pin above
      // pass no matter which day's strain was read. Prove the bonus is live and
      // unclamped for this series before trusting the pin.
      final zero = buildCrossDayBundle(_days(7, strainToday: 0), profile);
      final heavy = buildCrossDayBundle(_days(7, strainToday: 18), profile);

      expect(
        _needSec(heavy) - _needSec(zero),
        closeTo(_bonusSec(18), 1e-6),
        reason: 'a strain of 18 must add its full (18/21)*45 min here, or the '
            'regression above is passing for the wrong reason',
      );
    });

    test("with no derived row for today, yesterday's strain is not used", () {
      // The most recent record in the list is YESTERDAY, and it reports a
      // strain of 18. Reading days.last positionally would apply its bonus.
      final noToday =
          buildCrossDayBundle(_days(7, todayDerived: false), profile);
      final explicitZero =
          buildCrossDayBundle(_days(7, strainToday: 0), profile);

      expect(
        _needSec(noToday),
        _needSec(explicitZero),
        reason: 'no row for today means no strain reading for today',
      );
    });
  });

  group('sleep need — the strain bonus is disclosed, not silent', () {
    test('strain_bonus_min reports the minutes that were added', () {
      final b = buildCrossDayBundle(_days(7, strainToday: 18), profile);
      // (18/21)*45 min = 38.57 min.
      expect(_strainBonus(b), 39);
    });

    test('strain_bonus_min is null when today produced no strain reading', () {
      final b = buildCrossDayBundle(_days(7), profile);
      // Assert the KEY is present and its value is null. Without the key check
      // this passes trivially against a bundle that never emitted the field.
      expect(_hasStrainBonusKey(b), isTrue);
      expect(_strainBonus(b), isNull,
          reason: 'null and a confident 0 are different claims: an absent '
              'strain reading silently withholds up to 45 min of need, and '
              'that is exactly what this field exists to surface');
    });

    test('strain_bonus_min is 0, not null, on a genuine rest day', () {
      // Today reported strain and it was zero. That is a measured rest day, not
      // an absent reading — the distinction the null case above depends on.
      final b = buildCrossDayBundle(_days(7, strainToday: 0), profile);
      expect(_strainBonus(b), 0);
    });

    test('the disclosed bonus is what was APPLIED, not the raw formula value',
        () {
      // sleepNeed clamps to an 11 h CEILING after adding, so against a high
      // baseline + debt the strain bonus is only partly realized. Disclosing
      // the raw (strain/21)*45 would state an increase the published need never
      // took. 8.75 h weekdays / 10 h weekends => habitual 8.75, OSD 10,
      // debt 1.25 h, baseline clamped to 9.5 h — leaving only part of the
      // bonus room under the ceiling.
      final b = buildCrossDayBundle(
        _days(7, strainToday: 18, weekdayTstMin: 525, freeTstMin: 600),
        profile,
      );
      final zero = buildCrossDayBundle(
        _days(7, strainToday: 0, weekdayTstMin: 525, freeTstMin: 600),
        profile,
      );
      final bonus = (_strainBonus(b) as num).toDouble();
      final applied = _needSec(b) - _needSec(zero);

      expect(bonus * 60, closeTo(applied, 60));
      expect(bonus * 60, lessThan(_bonusSec(18)),
          reason: 'the ceiling binds, so a strain of 18 cannot add its full '
              '38.6 min of need here');
    });
  });

  group('strainBonusCaption — what the coach card actually says', () {
    test('an applied bonus is spelled out with its sign', () {
      expect(strainBonusCaption(39), "+39m added for today's strain");
    });

    test('an hour-plus bonus reads in h/m', () {
      // Not reachable through sleepNeed's 45 min cap today, but _dur is shared
      // and the caption must not render "75m" if that cap ever moves.
      expect(strainBonusCaption(75), "+1h 15m added for today's strain");
    });

    test('no strain reading today produces no line', () {
      // Matches the nap credit: the card stays silent rather than inventing
      // "+0m". The bundle still distinguishes null from 0 for anything that
      // needs to act on it.
      expect(strainBonusCaption(null), isNull);
    });

    test('a measured rest day produces no line', () {
      expect(strainBonusCaption(0), isNull);
    });

    test('a bonus fully swallowed by the clamp produces no line', () {
      // Applied 0 against a real strain reading: nothing was added, so there is
      // nothing to disclose. Claiming "+0m" would be noise.
      expect(strainBonusCaption(0), isNull);
    });
  });
}
