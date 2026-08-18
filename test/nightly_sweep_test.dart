// The nightly sweep's bar, as a pure function.
//
// The failure this is defending against is not a crash. It is a note that
// fires every night, restates the day, and trains the user to swipe it away —
// so the tests that matter most here are the SILENT ones.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/ai/nightly_sweep.dart';

/// A flat-ish history with a little quantized jitter, like a real series.
List<double> _steady(double around, int n) =>
    [for (var i = 0; i < n; i++) around + (i % 3) - 1];

SweepSeries _rhr(double today, List<double> history) => SweepSeries(
      key: 'rhr',
      label: 'resting heart rate',
      unit: 'bpm',
      today: today,
      history: history,
    );

void main() {
  group('silence is the normal answer', () {
    test('an ordinary day produces nothing', () {
      expect(sweepFindings([_rhr(54, _steady(54, 60))]), isEmpty);
    });

    test('a new user has no baseline, so nothing is unusual yet', () {
      // Thirteen days is not a "usual" to be unusual against, and the honest
      // output of not knowing is not a hedged guess — it is nothing.
      expect(sweepFindings([_rhr(90, _steady(54, 13))]), isEmpty);
    });

    test('a perfectly flat history cannot contain an unusual day', () {
      // MAD and SD both zero: no scale, no z, no finding. This is where a
      // naive robust-z divides by zero and starts reporting every day.
      expect(
        sweepFindings([_rhr(54, List<double>.filled(40, 54))]),
        isEmpty,
      );
    });

    test('a new extreme that is barely outside the range is arithmetic, '
        'not news', () {
      final h = _steady(54, 40); // spans 53–55
      expect(sweepFindings([_rhr(55.2, h)]), isEmpty);
    });

    test('an empty input list is fine', () {
      expect(sweepFindings(const []), isEmpty);
      expect(sweepInputs(const []), isEmpty);
      expect(sweepHeadline(const []), isNull);
    });
  });

  group('a finding carries its own evidence', () {
    test('names the value, the window and the usual range', () {
      final f = sweepFindings([_rhr(68, _steady(54, 45))]);
      expect(f, hasLength(1));
      expect(f.first.text, contains('resting heart rate 68 bpm'));
      expect(f.first.text, contains('days')); // the window it was measured over
      expect(f.first.text, contains('usually'));
      expect(f.first.high, isTrue);
    });

    test('direction is stated, never scored', () {
      final low = sweepFindings([_rhr(38, _steady(54, 45))]).first;
      expect(low.high, isFalse);
      for (final word in ['good', 'bad', 'poor', 'excellent', 'score']) {
        expect(low.text.toLowerCase(), isNot(contains(word)));
      }
    });

    test('minutes read as hours and minutes, not as a bare count', () {
      final f = sweepFindings([
        SweepSeries(
          key: 'tst_min',
          label: 'time asleep',
          unit: 'min',
          today: 290,
          history: _steady(430, 45),
        )
      ]);
      expect(f.first.text, contains('4h 50m'));
    });

    test('strongest first — the notification carries only that one', () {
      final f = sweepFindings([
        _rhr(60, _steady(54, 45)), // moderate
        SweepSeries(
          key: 'rmssd',
          label: 'HRV',
          unit: 'ms',
          today: 12,
          history: _steady(60, 45),
        ), // extreme
      ]);
      expect(f.first.key, 'rmssd');
      expect(sweepHeadline(f), startsWith('HRV'));
    });
  });

  group('two findings on one day are two findings', () {
    test('the pairing states coincidence and refuses a cause', () {
      final f = sweepFindings([
        _rhr(68, _steady(54, 45)),
        SweepSeries(
          key: 'rmssd',
          label: 'HRV',
          unit: 'ms',
          today: 18,
          history: _steady(60, 45),
        ),
      ]);
      final pair = sweepPairing(f)!;
      expect(pair, contains('same day'));
      expect(pair, contains('not a measured relationship'));
      for (final word in ['caused', 'because', 'due to']) {
        expect(pair.toLowerCase(), isNot(contains(word)));
      }
    });

    test('one finding is not a pair', () {
      expect(sweepPairing(sweepFindings([_rhr(68, _steady(54, 45))])), isNull);
    });
  });

  group('the payload is exactly what is sent', () {
    test('findings and the bedtime evidence, and nothing else', () {
      final f = sweepFindings([_rhr(68, _steady(54, 45))]);
      final inputs = sweepInputs(f, recommendedBedtime: '22:45');
      expect(inputs.keys.toSet(), {'unusual_for_you', 'recommended_bedtime'});
      expect((inputs['unusual_for_you'] as List).first, f.first.text);
    });

    test('no bedtime means no key — absent stays absent', () {
      final inputs = sweepInputs(sweepFindings([_rhr(68, _steady(54, 45))]));
      expect(inputs.containsKey('recommended_bedtime'), isFalse);
    });

    test('nothing found means an empty payload, and so no request at all', () {
      expect(sweepInputs(sweepFindings([_rhr(54, _steady(54, 60))])), isEmpty);
    });
  });
}
