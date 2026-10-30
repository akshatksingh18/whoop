import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_analytics/onehz.dart' as ana;
import 'package:whoop_companion/compute/onehz_pipeline.dart';
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/substrate.dart';

List<double> wave(int n) =>
    List.generate(n, (i) => 1000 + 40 * math.sin(2 * math.pi * 0.25 * i));

void main() {
  test(
    'reporting estimate records 0, 5 and 15 percent omissions without a gate',
    () {
      for (final missing in [0, 5, 15]) {
        final counts = List.generate(100, (i) => i < missing ? 0 : 1);
        final q = ana.beatReportingQuality(List.filled(100, 60), counts)!;
        expect(q['omitted_beat_share_estimate'], closeTo(missing / 100, 1e-9));
        expect(q['records_with_hr'], 100);
      }
      expect(ana.beatReportingQuality([0], [0]), isNull);
      expect(ana.beatReportingQuality([60], [-1]), isNull);
    },
  );
  test(
    'decoded per-record counts survive JSON and slicing; old payloads stay unknown',
    () {
      final sub = substrateFromDecodedPage(
        [
          {'rec_ts': 100, 'hr': 60},
          {'rec_ts': 101, 'hr': 60},
        ],
        [
          {'rec_ts': 100, 'rr_ms': 1000, 'beat_ts_ms': 100000},
        ],
      );
      expect(sub.rrCount, [1, 0]);
      expect(Substrate.fromJson(sub.toJson()).slice(101, 102).rrCount, [0]);
      final old = sub.toJson()..remove('rr_count');
      expect(Substrate.fromJson(old).rrCount, isEmpty);
    },
  );
  test('quality metadata does not change or withhold nightly RMSSD', () {
    const start = 1767225600, n = 2100;
    final rr = List.generate(
      n,
      (i) => 1000 + 40 * math.sin(2 * math.pi * i / 10),
    );
    final input = <String, dynamic>{
      'date': '2026-01-01',
      'device_family': 'gen4',
      'sleep_onset_sec': start,
      'sleep_offset_sec': start + n,
      'sleep_rr_ms': rr,
      'sleep_rr_ts_ms': List.generate(n, (i) => (start + i) * 1000.0),
      'sleep_ts': List.generate(n, (i) => start + i),
      'sleep_hr': List.filled(n, 60),
      'hypno_stages': List.filled(n, 'light'),
      'sleep_json': {'tst_sec': n},
    };
    final before = deriveDayBundle(input);
    input['sleep_rr_count'] = List.generate(n, (i) => i % 5 == 0 ? 0 : 1);
    final after = deriveDayBundle(input);
    final original = (before['scalars'] as Map)['rmssd'];
    expect(original, isNotNull);
    expect((after['scalars'] as Map)['rmssd'], original);
    expect((after['scalars'] as Map)['rr_omitted_share'], closeTo(.2, 1e-9));
  });
  test('clock re-anchor metadata leaves NN values and timing unchanged', () {
    final rr = List<double>.filled(20, 1000);
    final times = List.generate(20, (i) => (i + (i >= 10 ? 4 : 0)) * 1000.0);
    final clock = ana.rrBeatClock(rr, rrTsMs: times);
    final corrected = ana.correctRr(rr, rrTsMs: times);
    expect(corrected.nn, rr);
    expect(corrected.nnTimesMs, clock.timesMs);
    expect(corrected.gapBefore.where((v) => v), hasLength(1));
    expect(corrected.gapBefore[10], true);
  });
  test(
    'a counted spectral segment requires 90 percent and excludes re-anchors',
    () {
      final t = List.generate(300, (i) => i + 1.0);
      final rr = List<double>.filled(300, 1000);
      expect(ana.spectralSegmentQualified(t, rr, 0, 300, 0, 300), true);
      expect(
        ana.spectralSegmentQualified(
          t,
          List.filled(300, 800),
          0,
          300,
          0,
          300,
          minCoverage: .1,
        ),
        false,
      );
      final gaps = List<bool>.filled(300, false)..[150] = true;
      expect(
        ana.spectralSegmentQualified(t, rr, 0, 300, 0, 300, gapBefore: gaps),
        false,
      );
    },
  );
  test(
    'HF scaling stays within five percent of sinusoid variance, including clean runs around a gap',
    () {
      final rr = wave(900);
      final normal = ana
          .hrvFreq(
            rr,
            List.generate(900, (i) => i * 1000.0),
            artifactFraction: 0,
          )
          .value!;
      expect(normal.hf, closeTo(40 * 40 / 2, 40 * 40 / 2 * .05));
      final gaps = List<bool>.filled(900, false)..[450] = true;
      final shifted = ana
          .hrvFreq(
            rr,
            List.generate(900, (i) => (i + (i >= 450 ? 4 : 0)) * 1000.0),
            artifactFraction: 0,
            gapBefore: gaps,
          )
          .value!;
      expect(shifted.hf, closeTo(40 * 40 / 2, 40 * 40 / 2 * .05));
    },
  );
  test(
    'HF and respiration withhold when every segment crosses a re-anchor',
    () {
      final rr = wave(900);
      final times = List.generate(900, (i) => (i + (i ~/ 20) * 2) * 1000.0);
      final gaps = List.generate(900, (i) => i > 0 && i % 20 == 0);
      final hf = ana.hrvFreq(rr, times, artifactFraction: 0, gapBefore: gaps);
      expect(hf.value?.hf, isNull);
      expect(
        ana
            .rsaRespRate(rr, times, artifactFraction: 0, gapBefore: gaps)
            .present,
        false,
      );
    },
  );
  test(
    'staging spectral features skip gapped windows and retain clean ones',
    () {
      final rr = wave(200);
      final accel = [const ana.AccelSample(90000, 0, 0, 1)];
      final clean = ana.remFeaturesForTest(
        rr,
        List.generate(200, (i) => i * 1000.0),
        accel,
        0,
        0,
      );
      expect(clean.lfhf, isNotNull);
      final gapped = ana.remFeaturesForTest(
        rr,
        List.generate(200, (i) => (i + (i ~/ 20) * 2) * 1000.0),
        accel,
        0,
        0,
      );
      expect(gapped.lfhf, isNull);
      expect(gapped.rk, isNull);
    },
  );
}
