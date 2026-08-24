// Regression tests for the READINESS ring BOUNCING to ~100 and back (#117, the
// ready→ready case).
//
// Root cause: the composite maps its weighted robust-z to a 0–100 score via a
// logistic `score = 100 / (1 + exp(-z))`. `robustZ` (analytics util) only nulls
// on EXACT-zero MAD; a near-degenerate baseline (e.g. duplicate-day pollution
// collapsing the window toward one value) has a tiny NON-zero MAD, so robustZ
// returns a huge z, the logistic saturates, and today's headline flashes ~100
// until a cleaner re-derive snaps it back — a ready→ready bounce the
// `overnight_state == 'ready'` gate can't catch (the state is `ready` throughout).
//
// The fix (`headlineReadinessScalar` / `kReadinessZCap`) abstains from a
// saturated, physiologically-impossible readiness rather than persisting the
// bogus ~100, so no wrong value is ever headlined on any surface. These tests pin
// the saturation → abstain behaviour and prove a clean derive is unaffected.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

void main() {
  // A near-constant but strictly-increasing baseline: tiny NON-zero MAD, exactly
  // the shape duplicate-day pollution produces (not the exact-zero-MAD blank).
  //
  // Used for HRV ONLY (quantum 0, unguarded) below — since the readinessComposite
  // sub-quantum-dispersion guard (analytics#26 follow-up) now checks stddev for
  // EVERY quantized input regardless of whether robustZ succeeded, this exact
  // shape on a whole-bpm RHR baseline (quantum 1) would be refused outright by
  // name (`baseline_dispersion_below_quantum`) before ever reaching the
  // logistic — a strictly earlier, more explicit catch of the same "no real
  // dispersion" problem, but a different one than the z-cap this file tests.
  final degenerate = [for (var i = 0; i < 28; i++) 60.0 + i * 0.001];
  // A healthy, well-spread baseline: a real robust-z, well within the cap. Used
  // for RHR in every case below so RHR always clears the quantum-dispersion
  // guard — HRV's near-degenerate baseline is what drives the saturation.
  final clean = [for (var i = 0; i < 28; i++) 50.0 + i.toDouble()];

  // TWO drivers, not one. `readinessComposite` refuses to renormalise a single
  // input up to an effective weight of 1.0, so a one-input fixture now abstains
  // before the logistic is ever reached — which would have made these tests
  // pass for the wrong reason. HRV (0.40) + RHR (0.30) clears that floor and
  // still drives the composite the same way, so the saturation path below is
  // the thing under test rather than the input-count rule.
  Metric<Readiness> composite(
    double hrv,
    double rhr,
    List<double> hrvBase, {
    List<double>? rhrBase,
  }) =>
      readinessComposite(
          [hrvInput(hrv, hrvBase), rhrInput(rhr, rhrBase ?? clean)]);

  group('headlineReadinessScalar', () {
    test('a near-degenerate baseline saturates the logistic → abstained', () {
      final sat = composite(61.0, 59.0, degenerate);
      // The bug precondition: it computes, and it saturates the rail.
      expect(sat.present, isTrue);
      expect(sat.value!.score, greaterThan(99),
          reason: 'tiny-MAD baseline → huge z → logistic pinned near 100');
      expect(sat.value!.compositeZ.abs(), greaterThan(kReadinessZCap));
      // The guard withholds it instead of headlining ~100.
      expect(headlineReadinessScalar(sat), isNull);
    });

    test('a clean baseline yields a real score, surfaced unchanged', () {
      final ok = composite(70.0, 60.0, clean);
      expect(ok.present, isTrue);
      expect(ok.value!.compositeZ.abs(), lessThanOrEqualTo(kReadinessZCap));
      final score = headlineReadinessScalar(ok);
      expect(score, isNotNull);
      expect(score, closeTo(ok.value!.score, 1e-9),
          reason: 'a legitimate score passes through untouched');
      expect(score!, lessThan(95),
          reason: 'a real composite never approaches the saturated rail');
    });

    test('ready→ready bounce: the headline never takes the saturated value', () {
      final sat = composite(61.0, 59.0, degenerate);
      final ok = composite(70.0, 60.0, clean);
      // Two consecutive re-derives of the SAME already-`ready` day: a saturated
      // pass then a clean pass. What the ring would headline for each:
      final surfaced = [sat, ok].map(headlineReadinessScalar).toList();
      expect(surfaced.first, isNull, reason: 'saturated derive → no number');
      expect(surfaced.last, isNotNull, reason: 'clean derive → the real score');
      // The saturated ~100 is never surfaced (no bounce to a bogus green 100).
      expect(surfaced.contains(sat.value!.score), isFalse);
      expect(surfaced.whereType<double>().every((v) => v < 95), isTrue);
    });

    test('exact-zero MAD stays the honest blank path (unchanged)', () {
      // Fully-quantised baseline → robustZ null → composite absent → '—', not
      // 100. RHR given the SAME flat baseline explicitly (not the default
      // `clean`) so it is refused too, exactly as the shared-baseline version
      // of this test refused both inputs before HRV/RHR baselines were split.
      final flat = composite(61.0, 59.0, List.filled(28, 60.0),
          rhrBase: List.filled(28, 60.0));
      expect(flat.present, isFalse);
      expect(headlineReadinessScalar(flat), isNull);
    });
  });
}
