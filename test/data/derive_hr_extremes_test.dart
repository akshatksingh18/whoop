// The day's HR extremes when the spike-suppressed peak and trough reject every
// sample: no rejected reading stands in for either, so both are absent. Real
// engine and SQLite; the seconds are authored, not a recording.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-hr-extremes'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';

  test('a day above the smoother ceiling has no peak or trough', () async {
    final start = localDayStartSec(day)! + 12 * 3600;
    for (var i = 0; i < 120; i++) {
      final ts = start + i;
      await LocalDb.insertRecord(
        RawRecord(
          counter: i + 1,
          packetType: 47,
          hex: 'authored-low-hr-$i',
          capturedAt: ts * 1000,
          recTs: ts,
        ),
        // Inside the substrate's plausible band (25-230) but above the no-age
        // ceiling (220): every second fails the smoother's reject.
        Sample(
          tsEpoch: ts,
          counter: i + 1,
          hr: 225 + i % 3,
          ax: 0,
          ay: 0,
          az: 1,
        ),
      );
    }
    await DerivationEngine().run(const Profile(), force: true);
    final payload =
        jsonDecode((await DayResultStore.read(day))!['payload_json'] as String)
            as Map;
    final stats = payload['hr_stats'] as Map;
    expect(stats['max'], isNull);
    expect(stats['min'], isNull);
    expect(stats['avg'], 226);
  });
}
