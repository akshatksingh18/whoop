// Build 90 (Akshat's option A): Recovery explains its score. Synthetic data.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/readiness_explain.dart';
import 'package:openstrap_edge/ui2/recent_hrv_card.dart';

String _d(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  test('the window matches the score: 28 nights, 60 days, at least 14', () {
    expect(kRecoveryBaselineMinNights, ana.readinessCompositeMinBaseline);
    final start = DateTime(2026, 6, 1);
    final series = [
      for (var i = 0; i < 100; i++)
        (date: _d(start.add(Duration(days: i))), value: i.toDouble()),
    ];
    final day = _d(start.add(const Duration(days: 100)));
    final base = recoveryBaseline(series, day);
    expect(base.length, 28);
    expect(base.last, 99, reason: 'strictly before the day');
    // A 70-day gap: nothing within 60 days, so no baseline.
    final gap = _d(start.add(const Duration(days: 170)));
    expect(recoveryBaseline(series, gap), isEmpty);
  });

  test('scale is median and MAD, falling back to SD only when MAD is 0', () {
    final s = recoveryScale([for (var i = 0; i < 15; i++) 50.0 + (i % 5)])!;
    expect(s.centre, 52);
    expect(s.spread, closeTo(1 * 1.4826, 1e-9));
    expect(recoveryScale([1, 2, 3]), isNull, reason: 'fewer than 14');
    final q = recoveryScale([
      for (var i = 0; i < 14; i++) i < 10 ? 58.0 : 59.0,
    ])!;
    expect(q.centre, closeTo(58 + 4 / 14, 1e-9), reason: 'mean, as z() uses');
    expect(q.spread, greaterThan(0), reason: 'mean/SD fallback');
  });

  test('words follow the spread', () {
    expect(usualWord(-2.5), 'Well below usual');
    expect(usualWord(-1.2), 'Below usual');
    expect(usualWord(0.4), 'About usual');
    expect(usualWord(1.5), 'Above usual');
    expect(usualWord(3), 'Well above usual');
  });

  test('points add up to the shown score exactly', () {
    // HRV −0.70, breathing −0.07, resting HR −0.05, sleep +0.02 → 31.
    final c = [-0.70, -0.05, 0.02, -0.07];
    final pts = recoveryPoints(c);
    final z = c.reduce((a, b) => a + b);
    final score = (100 / (1 + math.exp(-z))).round();
    expect(score, 31);
    expect(pts.reduce((a, b) => a + b), score - 50);
    expect(pts[0], -17, reason: 'HRV carries most of it');
    expect(
      pts[0].abs(),
      greaterThan(pts.skip(1).map((p) => p.abs()).reduce(math.max)),
    );
    expect(recoveryPoints(const []), isEmpty);
    // A good night adds up the other way.
    final up = recoveryPoints([0.8, 0.3, 0.1]);
    expect(
      up.reduce((a, b) => a + b),
      (100 / (1 + math.exp(-1.2))).round() - 50,
    );
  });

  test('recent HRV: last night, its usual band and the 7-night average', () {
    final start = DateTime(2026, 9, 1);
    final ms = [for (var i = 0; i < 29; i++) 52.0 + (i * 7 % 9), 41.0];
    final series = [
      for (var i = 0; i < ms.length; i++)
        (date: _d(start.add(Duration(days: i))), value: math.log(ms[i])),
    ];
    final day = series.last.date;
    final v = recentHrv(series, day);
    expect(v.nights.length, 14);
    expect(v.last, closeTo(41, 1e-9));
    expect(v.lastDate, day);
    expect(v.usual, isNotNull);
    expect(v.usual!.lo, greaterThan(41));
    expect(v.avg7, isNotNull);
    expect(
      RecentHrvCard.sentence(v, today: day),
      contains('41 ms last night, below your usual'),
    );
    expect(
      RecentHrvCard.sentence(v, today: day),
      contains('one night, not a trend'),
    );
    // Build 91 (F08): an older day names its date, never "last night".
    final later = _d(DateTime.parse(day).add(const Duration(days: 3)));
    expect(
      RecentHrvCard.sentence(v, today: later),
      isNot(contains('last night')),
    );
    expect(RecentHrvCard.sentence(v, today: later), contains('41 ms on '));
  });

  test('a missing night or a short history says so, never a number', () {
    final start = DateTime(2026, 9, 1);
    final series = [
      for (var i = 0; i < 5; i++)
        (date: _d(start.add(Duration(days: i))), value: math.log(55)),
    ];
    final v = recentHrv(series, series.last.date);
    expect(v.usual, isNull);
    expect(RecentHrvCard.sentence(v), contains('after 14 measured nights'));
    final skipped = recentHrv(series, _d(start.add(const Duration(days: 9))));
    expect(skipped.last, isNull);
    expect(
      RecentHrvCard.sentence(skipped, today: skipped.day),
      'No HRV measured last night.',
    );
  });

  test('the 7-night average is judged on its own side (Build 91, F08)', () {
    RecentHrvView view(double last, double avg) => (
      day: '2026-09-20',
      nights: [(date: '2026-09-20', ms: last)],
      usual: (lo: 50.0, hi: 60.0),
      avg7: avg,
      last: last,
      lastDate: '2026-09-20',
    );
    final opposite = RecentHrvCard.sentence(view(40, 70), today: '2026-09-20');
    expect(opposite, contains('40 ms last night, below your usual 50–60'));
    expect(opposite, contains('70 ms, is above it'));
    expect(opposite, isNot(contains('below it too')));
    final both = RecentHrvCard.sentence(view(40, 45), today: '2026-09-20');
    expect(both, contains('is below it too'));
  });
}
