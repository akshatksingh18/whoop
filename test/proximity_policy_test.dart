// Tests for the find-my-band proximity policy. RSSI is noisy enough that the
// smoothing and the hysteresis ARE the feature — a raw reading would flicker
// between labels several times a second while the phone sits still.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/proximity_policy.dart';

void main() {
  group('warm-up', () {
    test('the first samples report unknown rather than a confident zone', () {
      final t = ProximityTracker();
      final first = t.add(-50);
      expect(first.zone, ProximityZone.unknown,
          reason: 'one read is as likely to be a multipath null as the truth');
      t.add(-50);
      final third = t.add(-50);
      expect(third.zone, ProximityZone.immediate);
    });

    test('trend is unknown until there is enough history', () {
      final t = ProximityTracker();
      expect(t.add(-70).trend, ProximityTrend.unknown);
      expect(t.current.smoothedRssi, -70);
    });

    test('current does not advance the sample count', () {
      final t = ProximityTracker()..add(-60);
      final a = t.current.samples;
      final b = t.current.samples;
      expect(a, b);
      expect(a, 1);
    });
  });

  group('zones', () {
    ProximityTracker settled(int rssi) {
      final t = ProximityTracker();
      for (var i = 0; i < 20; i++) {
        t.add(rssi);
      }
      return t;
    }

    test('a strong signal is immediate', () {
      expect(settled(-45).current.zone, ProximityZone.immediate);
    });

    test('a mid signal is near', () {
      expect(settled(-70).current.zone, ProximityZone.near);
    });

    test('a weak signal is far', () {
      expect(settled(-83).current.zone, ProximityZone.far);
    });

    test('a very weak signal admits it is barely usable', () {
      expect(settled(-95).current.zone, ProximityZone.veryFar);
    });
  });

  group('smoothing', () {
    test('one dropout does not move the label', () {
      final t = ProximityTracker();
      for (var i = 0; i < 15; i++) {
        t.add(-55);
      }
      expect(t.current.zone, ProximityZone.immediate);

      // A single catastrophic read — a hand over the band, a multipath null.
      final after = t.add(-100);
      expect(after.zone, ProximityZone.immediate,
          reason: 'a lone bad sample must not throw the hunt off');
    });

    test('a sustained change does move it', () {
      final t = ProximityTracker();
      for (var i = 0; i < 15; i++) {
        t.add(-50);
      }
      expect(t.current.zone, ProximityZone.immediate);
      for (var i = 0; i < 25; i++) {
        t.add(-92);
      }
      expect(t.current.zone, ProximityZone.veryFar);
    });

    test('the EWMA sits between the old value and the new sample', () {
      final t = ProximityTracker(alpha: 0.5);
      t.add(-40);
      final r = t.add(-60);
      expect(r.smoothedRssi, closeTo(-50, 0.001));
    });
  });

  group('hysteresis', () {
    test('a signal parked on a boundary does not flicker', () {
      // -60 is exactly the immediate/near floor.
      final t = ProximityTracker();
      for (var i = 0; i < 15; i++) {
        t.add(-60);
      }
      final settledZone = t.current.zone;

      // Wobble either side of the boundary by less than the hysteresis margin.
      final seen = <ProximityZone>{};
      for (var i = 0; i < 30; i++) {
        seen.add(t.add(i.isEven ? -59 : -61).zone);
      }
      expect(seen, {settledZone},
          reason: 'boundary noise must not repaint the label');
    });

    test('a decisive crossing is still respected', () {
      final t = ProximityTracker();
      for (var i = 0; i < 15; i++) {
        t.add(-62);
      }
      expect(t.current.zone, ProximityZone.near);
      for (var i = 0; i < 20; i++) {
        t.add(-50);
      }
      expect(t.current.zone, ProximityZone.immediate);
    });
  });

  group('trend — the actual hot/cold guidance', () {
    test('walking toward the band reads warmer', () {
      final t = ProximityTracker();
      for (var rssi = -90; rssi <= -50; rssi += 2) {
        t.add(rssi);
      }
      expect(t.current.trend, ProximityTrend.warmer);
    });

    test('walking away reads colder', () {
      final t = ProximityTracker();
      for (var rssi = -50; rssi >= -90; rssi -= 2) {
        t.add(rssi);
      }
      expect(t.current.trend, ProximityTrend.colder);
    });

    test('standing still reads steady, not a coin flip', () {
      final t = ProximityTracker();
      for (var i = 0; i < 40; i++) {
        t.add(i.isEven ? -70 : -71);
      }
      expect(t.current.trend, ProximityTrend.steady);
    });
  });

  group('strength bar', () {
    test('is null before any sample and bounded after', () {
      final t = ProximityTracker();
      expect(t.current.strength, isNull);
      for (var i = 0; i < 10; i++) {
        t.add(-20); // absurdly strong
      }
      expect(t.current.strength, 1.0);

      final weak = ProximityTracker();
      for (var i = 0; i < 10; i++) {
        weak.add(-120); // absurdly weak
      }
      expect(weak.current.strength, 0.0);
    });

    test('rises monotonically with signal', () {
      double at(int rssi) {
        final t = ProximityTracker();
        for (var i = 0; i < 30; i++) {
          t.add(rssi);
        }
        return t.current.strength!;
      }

      expect(at(-90), lessThan(at(-70)));
      expect(at(-70), lessThan(at(-50)));
    });
  });

  test('reset clears the state so a new hunt is not seeded by the last', () {
    final t = ProximityTracker();
    for (var i = 0; i < 20; i++) {
      t.add(-45);
    }
    expect(t.current.zone, ProximityZone.immediate);
    t.reset();
    expect(t.current.zone, ProximityZone.unknown);
    expect(t.current.smoothedRssi, isNull);
    expect(t.current.samples, 0);
    // First sample after a reset seeds the EWMA outright, not from the old one.
    expect(t.add(-90).smoothedRssi, -90);
  });

  test('every zone and trend has user-facing wording', () {
    for (final z in ProximityZone.values) {
      expect(z.label, isNotEmpty);
      expect(z.hint, isNotEmpty);
    }
    for (final t in ProximityTrend.values) {
      expect(t.label, isNotNull);
    }
  });
}
