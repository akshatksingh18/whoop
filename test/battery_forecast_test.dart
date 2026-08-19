// Tests for the overnight battery forecast. The whole point of this policy is
// that it abstains rather than guesses, so most of these assert SILENCE.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/battery_forecast.dart';

void main() {
  const f = BatteryForecaster();

  final now = DateTime(2026, 7, 28, 20, 0); // 20:00 local
  final wake = DateTime(2026, 7, 29, 7, 0); // 07:00 next day → 11 h away
  int secOf(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  /// A steady discharge run ending `now` at [endPct], losing [ratePctPerHour],
  /// sampled every [everyMin] minutes over [hours].
  List<BatterySample> run({
    required double endPct,
    required double ratePctPerHour,
    double hours = 6,
    int everyMin = 30,
    bool charging = false,
  }) {
    final out = <BatterySample>[];
    final steps = (hours * 60 / everyMin).round();
    for (var i = 0; i <= steps; i++) {
      final minsAgo = i * everyMin;
      out.add(BatterySample(
        tsSec: secOf(now.subtract(Duration(minutes: minsAgo))),
        pct: endPct + ratePctPerHour * (minsAgo / 60.0),
        charging: charging,
      ));
    }
    return out;
  }

  group('abstains rather than guessing', () {
    test('no samples at all', () {
      final r = f.forecast(samples: const [], now: now, wakeAt: wake);
      expect(r.isUsable, isFalse);
      expect(r.drainPctPerHour, isNull);
      expect(r.note, startsWith('need_history:'));
    });

    test('on the charger — the question is moot', () {
      final r = f.forecast(
        samples: run(endPct: 40, ratePctPerHour: 2, charging: true),
        now: now,
        wakeAt: wake,
      );
      expect(r.note, ForecastNote.charging);
      expect(r.predictedPctAtWake, isNull);
    });

    test('too few samples in the run', () {
      final r = f.forecast(
        samples: run(endPct: 50, ratePctPerHour: 2, hours: 1, everyMin: 30),
        now: now,
        wakeAt: wake,
      );
      expect(r.isUsable, isFalse);
      expect(r.note, startsWith('need_'));
    });

    test('enough samples but too short a span to trust a slope', () {
      // 6 samples inside 30 minutes: plenty of points, no leverage.
      final r = f.forecast(
        samples: run(endPct: 50, ratePctPerHour: 2, hours: 0.5, everyMin: 6),
        now: now,
        wakeAt: wake,
      );
      expect(r.isUsable, isFalse);
      expect(r.note, startsWith('need_span:'));
    });

    test('a flat battery series is not a drain rate', () {
      final r = f.forecast(
        samples: run(endPct: 80, ratePctPerHour: 0),
        now: now,
        wakeAt: wake,
      );
      expect(r.note, ForecastNote.notDraining);
    });

    test('an implausible rate is treated as an artefact, not a crisis', () {
      final r = f.forecast(
        samples: run(endPct: 10, ratePctPerHour: 60),
        now: now,
        wakeAt: wake,
      );
      expect(r.note, ForecastNote.rateImplausible);
      expect(f.willNotSurvive(r), isFalse,
          reason: 'an abstention must never raise an alarm');
    });

    test('stale samples are ignored entirely', () {
      final old = [
        for (var i = 0; i < 20; i++)
          BatterySample(
            tsSec: secOf(now.subtract(Duration(hours: 72 + i))),
            pct: 90.0 - i,
            charging: false,
          ),
      ];
      final r = f.forecast(samples: old, now: now, wakeAt: wake);
      expect(r.isUsable, isFalse);
    });
  });

  group('projects a real discharge run', () {
    test('a steady 2%/h run from 40% does not survive 11 hours', () {
      final r = f.forecast(
        samples: run(endPct: 40, ratePctPerHour: 2),
        now: now,
        wakeAt: wake,
      );
      expect(r.isUsable, isTrue);
      expect(r.drainPctPerHour, closeTo(2.0, 0.15));
      expect(r.currentPct, closeTo(40, 0.01));
      // 40 − 2×11 = 18 … below zero? No: 18 is positive, so it SURVIVES.
      expect(r.predictedPctAtWake, closeTo(18, 2));
      expect(f.willNotSurvive(r), isFalse);
    });

    test('the same rate from 15% does not make it to morning', () {
      final r = f.forecast(
        samples: run(endPct: 15, ratePctPerHour: 2),
        now: now,
        wakeAt: wake,
      );
      expect(r.isUsable, isTrue);
      expect(f.willNotSurvive(r), isTrue);
      expect(r.predictedPctAtWake, lessThan(0),
          reason: 'the shortfall is reported, not clamped to zero');
      expect(r.predictedEmptyAt!.isBefore(wake), isTrue);
    });

    test('the empty-at time lands where the rate says it should', () {
      final r = f.forecast(
        samples: run(endPct: 20, ratePctPerHour: 4),
        now: now,
        wakeAt: wake,
      );
      // 20% at 4%/h ⇒ ~5 h ⇒ about 01:00.
      expect(r.predictedEmptyAt!.difference(now).inMinutes, closeTo(300, 45));
    });

    test('a single stuck reading does not drag the estimate (Theil–Sen)', () {
      final clean = run(endPct: 30, ratePctPerHour: 3);
      final withOutlier = [...clean];
      // Corrupt one mid-run sample by 25 points — an OLS fit would visibly tilt.
      withOutlier[3] = BatterySample(
        tsSec: withOutlier[3].tsSec,
        pct: withOutlier[3].pct + 25,
        charging: false,
      );
      final a = f.forecast(samples: clean, now: now, wakeAt: wake);
      final b = f.forecast(samples: withOutlier, now: now, wakeAt: wake);
      expect(b.drainPctPerHour, closeTo(a.drainPctPerHour!, 0.5));
    });
  });

  group('run detection', () {
    test('a charge event ends the run — the rate is measured after it only', () {
      // Older: charging at a high level. Newer: a clean 3%/h discharge.
      final recent = run(endPct: 55, ratePctPerHour: 3, hours: 5);
      final older = [
        for (var i = 1; i <= 10; i++)
          BatterySample(
            tsSec: secOf(now.subtract(Duration(hours: 5, minutes: i * 20))),
            pct: 60 + i.toDouble(),
            charging: true,
          ),
      ];
      final r = f.forecast(
        samples: [...recent, ...older],
        now: now,
        wakeAt: wake,
      );
      expect(r.isUsable, isTrue);
      expect(r.drainPctPerHour, closeTo(3.0, 0.4),
          reason: 'a rate measured across a charge is not a rate');
      expect(r.samplesUsed, lessThanOrEqualTo(recent.length));
    });

    test('unordered input is handled', () {
      final s = run(endPct: 25, ratePctPerHour: 2.5)..shuffle();
      final r = f.forecast(samples: s, now: now, wakeAt: wake);
      expect(r.isUsable, isTrue);
      expect(r.drainPctPerHour, closeTo(2.5, 0.3));
    });
  });

  group('nextWakeTime', () {
    test('later today when the wake minute is still ahead', () {
      final n = DateTime(2026, 7, 28, 5, 0);
      final w = BatteryForecaster.nextWakeTime(n, 7 * 60);
      expect(w, DateTime(2026, 7, 28, 7, 0));
    });

    test('tomorrow when it has already passed — the evening case', () {
      final n = DateTime(2026, 7, 28, 21, 30);
      final w = BatteryForecaster.nextWakeTime(n, 7 * 60);
      expect(w, DateTime(2026, 7, 29, 7, 0));
    });

    test('exactly at the wake minute rolls to tomorrow, never zero-length', () {
      final n = DateTime(2026, 7, 28, 7, 0);
      final w = BatteryForecaster.nextWakeTime(n, 7 * 60);
      expect(w, DateTime(2026, 7, 29, 7, 0));
      expect(w.isAfter(n), isTrue);
    });

    test('the WALL-CLOCK hour is preserved when rolling to tomorrow', () {
      // This is the property DST breaks. `add(Duration(days: 1))` is absolute
      // elapsed time, so across a transition it lands at 06:00 or 08:00 rather
      // than the 07:00 the user set — and hours-to-wake, and everything built
      // on it, shifts by an hour. Asserting the wall clock rather than the
      // instant is what makes the constructor-vs-Duration distinction visible.
      // (In a UTC test environment there is no transition to cross, so this
      // pins the intent; the guarantee itself lives in the constructor.)
      for (final month in [1, 3, 6, 10, 11]) {
        final n = DateTime(2026, month, 28, 23, 30);
        final w = BatteryForecaster.nextWakeTime(n, 7 * 60);
        expect(w.hour, 7, reason: 'month $month');
        expect(w.minute, 0, reason: 'month $month');
        expect(w.isAfter(n), isTrue);
      }
    });

    test('rolls correctly across a month end', () {
      final n = DateTime(2026, 1, 31, 23, 0);
      expect(BatteryForecaster.nextWakeTime(n, 7 * 60),
          DateTime(2026, 2, 1, 7, 0));
    });

    test('rolls correctly across a year end', () {
      final n = DateTime(2026, 12, 31, 23, 0);
      expect(BatteryForecaster.nextWakeTime(n, 6 * 60 + 30),
          DateTime(2027, 1, 1, 6, 30));
    });
  });

  group('inEveningWindow — only warn while it is still actionable', () {
    const bed22 = 22 * 60;

    test('fires in the run-up to a 22:00 bedtime', () {
      expect(BatteryForecaster.inEveningWindow(19 * 60, bed22), isTrue);
      expect(BatteryForecaster.inEveningWindow(21 * 60 + 59, bed22), isTrue);
    });

    test('silent in the middle of the night — waking you helps nobody', () {
      expect(BatteryForecaster.inEveningWindow(2 * 60, bed22), isFalse);
      expect(BatteryForecaster.inEveningWindow(4 * 60, bed22), isFalse);
    });

    test('silent in the morning — forgotten long before evening', () {
      expect(BatteryForecaster.inEveningWindow(9 * 60, bed22), isFalse);
      expect(BatteryForecaster.inEveningWindow(13 * 60, bed22), isFalse);
    });

    test('boundaries: inclusive at the start, exclusive at bedtime', () {
      expect(BatteryForecaster.inEveningWindow(18 * 60, bed22), isTrue);
      expect(BatteryForecaster.inEveningWindow(18 * 60 - 1, bed22), isFalse);
      expect(BatteryForecaster.inEveningWindow(bed22, bed22), isFalse);
    });

    test('wraps midnight for a late bedtime (01:00 ⇒ 21:00–01:00)', () {
      const bed1am = 60;
      expect(BatteryForecaster.inEveningWindow(23 * 60, bed1am), isTrue);
      expect(BatteryForecaster.inEveningWindow(30, bed1am), isTrue);
      expect(BatteryForecaster.inEveningWindow(20 * 60, bed1am), isFalse);
      expect(BatteryForecaster.inEveningWindow(2 * 60, bed1am), isFalse);
    });

    test('an early bedtime wraps the other way (21:00 for a 00:00 bed)', () {
      expect(BatteryForecaster.inEveningWindow(22 * 60, 0), isTrue);
      expect(BatteryForecaster.inEveningWindow(19 * 60, 0), isFalse);
    });
  });

  test('describe() only speaks when there are numbers behind it', () {
    final abstained = f.forecast(samples: const [], now: now, wakeAt: wake);
    expect(BatteryForecaster.describe(abstained, wakeAt: wake), isEmpty);

    final real = f.forecast(
      samples: run(endPct: 15, ratePctPerHour: 2),
      now: now,
      wakeAt: wake,
    );
    expect(BatteryForecaster.describe(real, wakeAt: wake), contains('%/h'));
  });

  test('describe() only claims "before you wake" when that is actually true',
      () {
    // Dies at ~07:30 on this rate — i.e. AFTER a 07:00 wake.
    final survives = f.forecast(
      samples: run(endPct: 40, ratePctPerHour: 2),
      now: now,
      wakeAt: wake,
    );
    expect(survives.predictedEmptyAt!.isAfter(wake), isTrue);
    expect(BatteryForecaster.describe(survives, wakeAt: wake),
        isNot(contains('before you wake')),
        reason: 'the text must follow the numbers, not the call site');

    final dies = f.forecast(
      samples: run(endPct: 15, ratePctPerHour: 2),
      now: now,
      wakeAt: wake,
    );
    expect(BatteryForecaster.describe(dies, wakeAt: wake),
        contains('before you wake'));
  });

  test('a forecast that trips the reserve never reads as survivable', () {
    // 25% at 20:00, 2%/h → 3% left at a 07:00 wake (under the 5% reserve, so
    // the alert FIRES) but 0% only at 08:30. The body used to say "runs out
    // around 08:30, after your usual wake time" under "Charge your strap
    // before bed" — the user reads the body and doesn't charge.
    final thin = f.forecast(
      samples: run(endPct: 25, ratePctPerHour: 2),
      now: now,
      wakeAt: wake,
    );
    expect(f.willNotSurvive(thin), isTrue);
    expect(thin.predictedEmptyAt!.isAfter(wake), isTrue);
    final body = BatteryForecaster.describe(thin, wakeAt: wake);
    expect(body, contains('Charge it now'));
    expect(body, contains('3% left'));
  });
}
