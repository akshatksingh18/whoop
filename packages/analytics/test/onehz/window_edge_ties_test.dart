import 'package:openstrap_analytics/onehz.dart';
import 'package:test/test.dart';

void main() {
  test('window gather keeps tied beats at both edges', () {
    final accel = <AccelSample>[
      for (var i = 0; i < 30; i++) AccelSample(i * 1000.0, 0, 0, 1),
    ];
    // Epoch [0,30) has midpoint 15 seconds. A five-second half-window is
    // therefore inclusive from 10000 through 20000 milliseconds.
    final timestamps = <double>[
      9000,
      10000,
      10000,
      10000,
      15000,
      20000,
      20000,
      20000,
      21000,
    ];
    final markedBeats = <double>[
      900,
      901,
      902,
      903,
      904,
      905,
      906,
      907,
      908,
    ];

    final result = cleanBeatsInWindowForTest(
      markedBeats,
      timestamps,
      accel,
      0,
      30,
      halfWinMs: 5000,
    );

    expect(result, [901, 902, 903, 904, 905, 906, 907]);
  });
}
