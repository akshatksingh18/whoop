// THE GAP HAS TO BE THE ONE THAT EXPLAINS THE ABSENCE.
//
// `_wearBlock` has written the day's off-wrist stretches on every derive since
// it existed and no widget has ever read one, so a new user — median wear on
// two of the three real databases is 15 % and 3 % — meets a wall of honest
// absences whose single shared cause was sitting in the same object.
//
// The failure this guards against is the opposite one: reaching for the
// nearest gap and printing a false cause with an unactionable fix, which costs
// more trust than the bare absence did.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/grammar.dart';

/// Local midnight of an arbitrary day, so the windows below read like a night.
final _mid = DateTime(2026, 8, 14).millisecondsSinceEpoch ~/ 1000;
int _at(num hours) => _mid + (hours * 3600).round();

Map<String, dynamic> _wear(List<List<num>> off) => {
      'segments': [
        for (final o in off)
          {'on': false, 'start': _at(o[0]), 'end': _at(o[1])},
      ],
    };

/// 8 PM the evening before → 10 AM, the window the Health rows ask about.
String? _night(List<Map<String, dynamic>?> wear) =>
    wearGapWhy(wear, fromSec: _at(-4), toSec: _at(10));

void main() {
  group('wearGapWhy', () {
    test('a night on the charger is named, in the local clock', () {
      // 11:20 PM → 2:14 AM, the sentence the whole item exists for.
      expect(_night([_wear([[-0.6666, 2.2333]])]),
          'Your band was off your wrist 11:20 PM – 2:14 AM.');
    });

    test('an afternoon gap does not explain a missing night', () {
      // Three hours off at 3 PM — long enough on its own, and outside the
      // window entirely. Saying nothing is the answer.
      expect(_night([_wear([[15, 18]])]), isNull);
    });

    test('a short hole in the night says nothing', () {
      // 40 minutes off at 1 AM. A shower or a dropped link is not why a night
      // went unscored, and something else is.
      expect(_night([_wear([[1, 1.6666]])]), isNull);
    });

    test('the two days are joined across midnight', () {
      // The same three-hour hole as the first case, as the engine actually
      // stores it: a trailing off-segment on one day and a leading one on the
      // next. Neither half clears the gate alone.
      final prev = _wear([[-0.6666, 0]]);
      final today = _wear([[0, 2.2333]]);
      // Alone, the evening half is under the floor and the morning half
      // reports a gap that began at midnight — which is when the day rolled
      // over, not when the band came off.
      expect(_night([prev]), isNull);
      expect(_night([today]),
          'Your band was off your wrist 12:00 AM – 2:14 AM.');
      expect(_night([prev, today]),
          'Your band was off your wrist 11:20 PM – 2:14 AM.');
    });

    test('the longest overlapping gap wins, not the first', () {
      expect(_night([_wear([[0, 1], [2, 8]])]),
          'Your band was off your wrist 2:00 AM – 8:00 AM.');
    });

    test('"we never looked" is not "the band was never off"', () {
      // An imported day carries no wear block, and an older bundle carries an
      // empty segment list. Neither is a measurement of continuous wear.
      expect(_night([null]), isNull);
      expect(_night([const {}]), isNull);
      expect(_night([_wear(const [])]), isNull);
    });
  });

  group('StatusCard.forMetric', () {
    // The rendering rule, asserted on the copy rather than on pixels: the
    // pipeline saw the day and keeps the first sentence, a sentence written
    // into a widget by someone who never saw the day does not.
    const gap = 'Your band was off your wrist 11:20 PM – 2:14 AM.';

    test('a measured gap replaces a reason the screen invented', () {
      final s = StatusCard.forMetric('No sleep', Metric.empty,
          why: 'No sleep period long enough to score was recorded.', gap: gap);
      expect(s!.why, gap);
    });

    test('the pipeline keeps its reason and the gap is added to it', () {
      final s = StatusCard.forMetric(
          'No respiratory rate', const Metric(note: 'need_input:name=nn_beats'),
          why: 'ignored', gap: gap);
      expect(s!.why, startsWith('Too few clean beat-to-beat intervals'));
      expect(s.why, endsWith(gap));
    });

    test('no gap leaves the card exactly as it was', () {
      final s = StatusCard.forMetric('No sleep', Metric.empty, why: 'because');
      expect(s!.why, 'because');
    });
  });
}
