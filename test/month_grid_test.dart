// What a shade is allowed to mean. `shadeCells` is pure, and the rule it
// enforces — no personal range, no shading at all — is the whole honesty of
// the picture.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show ChartPoint;
import 'package:openstrap_edge/ui2/screens/month_grid.dart';

void main() {
  group('a shade is a place in your own range', () {
    // Dated backwards from NOW, because `denseDays` lays a window out ending
    // today — a fixture pinned to a calendar date silently loses however many
    // days have passed since somebody wrote it.
    List<ChartPoint> pts(List<double> vs) => [
          for (var i = 0; i < vs.length; i++)
            (
              t: DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch ~/
                  1000,
              v: vs[i],
            ),
        ];

    test('too little history is no shade at all, not a pale one', () {
      final short = List<double>.generate(kGridMinHistory - 1, (i) => 40 + i * 1.0);
      final r = gridRow('readiness', pts(short));
      expect(r.shaded, isFalse);
      expect(r.cells.every((v) => v == null), isTrue);
    });

    test('cells run 0 to 1 across the 10th–90th percentile, clamped', () {
      final h = List<double>.generate(100, (i) => i.toDouble());
      final out = shadeCells([0, 50, 99, null], h);
      expect(out[0], 0.0); // below p10 clamps rather than going negative
      expect(out[1], closeTo(.5, .05));
      expect(out[2], 1.0);
      // An absent day stays absent. It is the outline, and the outline is the
      // whole honesty of the picture.
      expect(out[3], isNull);
    });

    test('a flat history has no inside, so every measured day is the middle',
        () {
      final out = shadeCells([7, null], List<double>.filled(30, 7));
      expect(out[0], .5);
      expect(out[1], isNull);
    });

    test('the count is coverage, and coverage cannot reset', () {
      final r = gridRow(
          'strain', pts(List<double>.generate(30, (i) => 5 + i % 7)));
      // 30 stored days ending today: every slot in the window is filled, and
      // the number the screen prints is a count, never a run.
      expect(r.have, kGridDays);
      expect(r.historyDays, 30);
    });
  });
}