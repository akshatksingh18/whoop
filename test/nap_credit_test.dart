// HONESTY REGRESSION — nap credit against tonight's sleep need.
//
// Naps are subtracted 1:1 from sleep need. Two bugs made that subtraction
// wrong in the same direction — always recommending LESS sleep than the user
// needs — and both were invisible, because the credit was applied inside
// `need_sec` with nothing surfacing it:
//
//   1. `nap_min` carried the nap's IN-BED span rather than time ASLEEP, so a
//      2 h lie-down at 70% efficiency credited 120 min instead of 84.
//   2. Today's credit was read with `_lastNum`, which walks BACKWARD through
//      the day records and returns the last non-null. On any day where nap
//      detection abstained, that silently credited YESTERDAY's naps.
//
// This file pins (2) and the new disclosure field. (1) is pinned in the
// analytics package, where TST and in-bed are now separate fields.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';

/// Minimal oldest-first day series with the fields sleep need actually reads.
///
/// [todayDerived] false models the common real case where today has no derived
/// row yet, so the most recent record in the list is YESTERDAY.
List<Map<String, dynamic>> _days(
  int n, {
  double? napMinToday,
  bool todayDerived = true,
}) {
  final out = <Map<String, dynamic>>[];
  var dt = DateTime(2024, 1, 1);
  for (var i = 0; i < n; i++) {
    final last = i == n - 1;
    out.add({
      // Stamped by _refreshCrossDayInputArtifact for today's row only.
      if (last && todayDerived) 'is_today': true,
      'date': '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}',
      'rhr': 55.0,
      'rmssd': 45.0,
      'readiness': 70.0,
      'onset_sec': 23 * 3600,
      'wake_sec': 31 * 3600,
      'tst_min': 450,
      'strain': 8.0,
      // Every day EXCEPT today reports a big nap. Today's is caller-controlled.
      if (!last) 'nap_min': 90.0,
      if (last && napMinToday != null) 'nap_min': napMinToday,
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

Object? _napCredit(Map<String, dynamic> bundle) =>
    ((bundle['sleep_coach'] as Map)['nap_credit_min']);

void main() {
  const profile = <String, dynamic>{};

  group('sleep need — nap credit is TODAY-scoped', () {
    test("a day with no nap reading is NOT credited yesterday's nap", () {
      // Today abstained; the 6 days before it each report a 90-minute nap.
      final noReading = buildCrossDayBundle(_days(7), profile);
      // Same series, but today explicitly reports zero nap minutes.
      final explicitZero =
          buildCrossDayBundle(_days(7, napMinToday: 0), profile);

      expect(
        _needSec(noReading),
        _needSec(explicitZero),
        reason: 'an absent nap reading must credit nothing — reaching back a '
            'day for a number is imputation, and it shortens the '
            'recommendation by a nap the user did not take today',
      );
    });

    test('a real nap today IS credited, minute for minute', () {
      final without = buildCrossDayBundle(_days(7, napMinToday: 0), profile);
      final with45 = buildCrossDayBundle(_days(7, napMinToday: 45), profile);

      expect(
        _needSec(without) - _needSec(with45),
        closeTo(45 * 60, 1e-6),
        reason: '45 min asleep should remove exactly 45 min of need',
      );
    });
  });

  group('sleep need — the credit is disclosed, not silent', () {
    test('nap_credit_min reports the minutes that were subtracted', () {
      final b = buildCrossDayBundle(_days(7, napMinToday: 45), profile);
      expect(_napCredit(b), 45);
    });

    test('nap_credit_min is null when today produced no nap reading', () {
      final b = buildCrossDayBundle(_days(7), profile);
      expect(_napCredit(b), isNull,
          reason: 'null and a confident 0 are different claims; the card '
              'must not render "−0m" for "we do not know"');
    });

    test('the disclosed credit is what was APPLIED, not the raw nap minutes',
        () {
      // sleepNeed clamps to a 6 h floor AFTER subtracting, so an enormous nap
      // credit is only partly realized. Disclosing the raw minutes would state
      // a reduction the published need never took.
      final b = buildCrossDayBundle(_days(7, napMinToday: 600), profile);
      final credit = (_napCredit(b) as num).toDouble();
      final applied =
          _needSec(buildCrossDayBundle(_days(7, napMinToday: 0), profile)) -
              _needSec(b);

      expect(credit * 60, closeTo(applied, 60));
      expect(credit, lessThan(600),
          reason: '10 h of nap cannot remove 10 h of need — the floor binds');
    });
  });

  group('sleep need — today must be identified, not assumed positional', () {
    test("with no derived row for today, yesterday's nap is not credited", () {
      // The most recent record in the list is YESTERDAY, and it reports a
      // 90-minute nap. Reading days.last positionally would credit it.
      final noToday =
          buildCrossDayBundle(_days(7, todayDerived: false), profile);
      final explicitZero =
          buildCrossDayBundle(_days(7, napMinToday: 0), profile);

      expect(_needSec(noToday), _needSec(explicitZero),
          reason: 'no row for today means no nap reading for today');
      expect(_napCredit(noToday), isNull);
    });
  });
}
