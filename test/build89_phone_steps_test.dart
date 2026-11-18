// Build 89: the personal build counts phone steps only. Band rows are stored
// but never enter a day's total — not over phone time, not to fill time the
// phone did not cover.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/live_coverage_policy.dart';

void main() {
  const h9 = 1000000 * 60;
  CoverageSpan phone(int from, int to, int n) =>
      CoverageSpan(startTs: from, endTs: to, steps: n, fromBand: false);
  CoverageSpan band(int from, int to, int n) =>
      CoverageSpan(startTs: from, endTs: to, steps: n, fromBand: true);

  test('band steps never fill time the phone did not cover', () {
    final rows = [
      phone(h9, h9 + 3600, 3000),
      // The phone was not counting from 10:00 to 11:00; the band was.
      band(h9 + 3600, h9 + 7200, 2500),
    ];
    expect(
      resolveDaySteps(rows, phoneFirst: true, bandSteps: true).total,
      5500,
    );
    final r = resolveDaySteps(rows, phoneFirst: true, bandSteps: false);
    expect(r.total, 3000);
    expect(r.strap, 0);
    expect(r.spans.every((s) => !s.fromBand), isTrue);
  });

  test('a day only the band measured has no step count', () {
    final r = resolveDaySteps(
      [band(h9, h9 + 3600, 4000)],
      phoneFirst: true,
      bandSteps: false,
    );
    expect(r.total, 0);
    expect(r.hasPhoneCoverage, isFalse);
    expect(r.coveredSeconds, 0);
  });

  test('a phone hour that confirmed zero steps stays zero', () {
    final r = resolveDaySteps(
      [phone(h9, h9 + 3600, 0), band(h9, h9 + 3600, 900)],
      phoneFirst: true,
      bandSteps: false,
    );
    expect(r.total, 0);
    expect(r.hasPhoneCoverage, isTrue);
  });
}
