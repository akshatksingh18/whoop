import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

Map<String, dynamic> night(List<String> labels) {
  const start = 1767225600;
  final asleep = labels
      .where((s) => s == 'light' || s == 'rem' || s == 'deep')
      .length;
  return deriveDayBundle({
    'date': '2026-01-01',
    'device_family': 'gen4',
    'sleep_onset_sec': start,
    'sleep_offset_sec': start + labels.length,
    'sleep_ts': List.generate(labels.length, (i) => start + i),
    'sleep_hr': List.filled(labels.length, 60),
    'hypno_stages': labels,
    'sleep_json': {
      'tst_sec': asleep,
      'in_bed_sec': labels.length,
      'unobserved_sec': labels.where((s) => s == 'unobserved').length,
      'waso_sec': labels.where((s) => s == 'wake').length,
    },
  });
}

void main() {
  test('sleep need repays a quarter of the gap, with no strain bonus', () {
    for (final strain in [0.0, 21.0]) {
      final need = ana.sleepNeed(
        baselineNeedSec: 8 * 3600,
        sleepDebtSec: 4 * 3600,
        dayStrain: strain,
        napCreditSec: 3600,
      );
      expect(need.value!.needSec, 8 * 3600);
      expect(need.inputs_used, isNot(contains('strain')));
    }
  });
  test('existing sleep need clamps stay in place', () {
    expect(
      ana
          .sleepNeed(
            baselineNeedSec: 8 * 3600,
            sleepDebtSec: 0,
            dayStrain: 0,
            napCreditSec: 8 * 3600,
          )
          .value!
          .needSec,
      6 * 3600,
    );
    expect(
      ana
          .sleepNeed(
            baselineNeedSec: 9 * 3600,
            sleepDebtSec: 12 * 3600,
            dayStrain: 0,
            napCreditSec: 0,
          )
          .value!
          .needSec,
      11 * 3600,
    );
  });
  test('static gain error is still; ten-degree rotation is restless', () {
    final static = [
      for (var i = 0; i < 300; i++) ana.AccelSample(i * 1000.0, 0, 0, 1.02),
    ];
    expect(ana.armAngleRestlessness(static).single['density'], 0);
    final rotation = [
      for (var i = 0; i < 300; i++)
        ana.AccelSample(
          i * 1000.0,
          i < 150 ? 0 : 1.02 * math.sin(10 * math.pi / 180),
          0,
          i < 150 ? 1.02 : 1.02 * math.cos(10 * math.pi / 180),
        ),
    ];
    expect(ana.armAngleRestlessness(rotation).single['density'], 1);
    expect(
      ana.armAngleRestlessness([
        const ana.AccelSample(0, 0, 0, 0),
        const ana.AccelSample(1000, 0, 0, 1, valid: false),
      ]),
      isEmpty,
    );
    expect(ana.armAngleRestlessness([static.first]), isEmpty);
  });
  test('one sustained awakening definition counts five-minute wake runs', () {
    final labels = [
      ...List.filled(300, 'light'),
      ...List.filled(299, 'wake'),
      ...List.filled(300, 'light'),
      ...List.filled(300, 'wake'),
      ...List.filled(300, 'light'),
    ];
    expect((night(labels)['scalars'] as Map)['awakenings'], 1);
  });
  test(
    'unavailable stages or unqualified cycles stay absent rather than zero',
    () {
      final empty = deriveDayBundle({'date': '2026-01-01'});
      expect((empty['sleep'] as Map)['cycle_count'], isNull);
      expect((empty['sleep'] as Map)['cycle_series'], isNull);
      final staged = night(List.filled(1800, 'light'));
      expect((staged['sleep'] as Map)['cycle_count'], isNull);
    },
  );
  test('a recording gap stays outside measured sleep duration', () {
    final bundle = night([
      ...List.filled(300, 'light'),
      ...List.filled(300, 'unobserved'),
      ...List.filled(300, 'light'),
    ]);
    expect((bundle['scalars'] as Map)['tst_min'], 10);
    expect((bundle['scalars'] as Map)['unobserved_min'], 5);
  });
  test('a complete five-minute wake before a recording gap counts once', () {
    final labels = [
      ...List.filled(300, 'light'),
      ...List.filled(300, 'wake'),
      ...List.filled(90, 'unobserved'),
      ...List.filled(300, 'light'),
    ];
    expect((night(labels)['scalars'] as Map)['awakenings'], 1);
    expect(ana.sleepRunShape(labels).awakenings, 1);
  });
}
