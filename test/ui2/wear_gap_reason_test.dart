// THE GAP HAS TO BE THE ONE THAT EXPLAINS THE ABSENCE.
//
// A measured reason reaches `StatusCard.forMetric` as `gap` (the readiness
// detail passes it for a held-over night). These tests pin how it ranks against
// the pipeline's own note and a reason a widget wrote without seeing the day.
//
// The failure this guards against is the opposite one: reaching for the
// nearest gap and printing a false cause with an unactionable fix, which costs
// more trust than the bare absence did.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/ui2/grammar.dart';

void main() {
  group('StatusCard.forMetric', () {
    // The rendering rule, asserted on the copy rather than on pixels: the
    // pipeline saw the day and keeps the first sentence, a sentence written
    // into a widget by someone who never saw the day does not.
    const gap = 'Your band was off your wrist 11:20 PM – 2:14 AM.';

    test('a measured gap replaces a reason the screen invented', () {
      final s = StatusCard.forMetric(
        'No sleep',
        Metric.empty,
        why: 'No sleep period long enough to score was recorded.',
        gap: gap,
      );
      expect(s!.why, gap);
    });

    test('the pipeline keeps its reason and the gap is added to it', () {
      final s = StatusCard.forMetric(
        'No respiratory rate',
        const Metric(note: 'need_input:name=nn_beats'),
        why: 'ignored',
        gap: gap,
      );
      expect(s!.why, startsWith('Too few clean beat-to-beat intervals'));
      expect(s.why, endsWith(gap));
    });

    test('no gap leaves the card exactly as it was', () {
      final s = StatusCard.forMetric('No sleep', Metric.empty, why: 'because');
      expect(s!.why, 'because');
    });
  });
}
