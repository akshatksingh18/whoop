// B88-01: the WHOOP 4.0 `skinTempRaw` field is not a temperature.
//
// The protocol decoder deprecates the u16 at inner offset 68 as an unknown
// optical-block quantity. Before Build 88 it was averaged, z-scored, fed to
// readiness (weight .08) and, through stored `skin_temp_z`, to the cross-day
// temperature-illness and anomaly detectors, which were also handed a z-score
// their own contracts refuse. These tests pin the repair: unknown WHOOP 4
// counts change no physiological output, stored/imported values never reach a
// cross-day detector, and a verified family (gen5) keeps its channel, fed to the
// detectors as the raw nightly mean they require.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

const int _t0 = 1786700000;
const int _sleepSec = 6 * 3600;

Map<String, dynamic> _bundle({required String? family, required int tempCount}) {
  final ts = <int>[for (var i = 0; i < _sleepSec; i++) _t0 + i];
  final hr = <int>[for (var i = 0; i < _sleepSec; i++) 54 + (i % 5)];
  final temp = List<int>.filled(_sleepSec, tempCount);
  return deriveDayBundle(
    DayBundleInput(
      date: '2026-10-10',
      dayTsSec: ts,
      dayHr: hr,
      sleepTsSec: ts,
      sleepHr: hr,
      sleepRrTsMs: const [],
      sleepRrMs: const [],
      sleepSkinTemp: temp,
      sleepJson: <String, dynamic>{'tst_sec': _sleepSec, 'efficiency_pct': 92.0},
      hypnoStages: const [],
      sleepOnsetSec: ts.first,
      sleepOffsetSec: ts.last + 1,
      profile: const {'age': 23, 'sex': 'm', 'weight_kg': 80, 'height_cm': 187},
      // 20 earlier nights of the same channel, with real spread, so the old
      // code had everything it needed to z-score and to use the readiness
      // temperature driver.
      skinTempAdcHistory: [for (var i = 0; i < 20; i++) 3000.0 + (i % 7) * 9],
      rhrHistory: [for (var i = 0; i < 20; i++) 54.0 + (i % 5)],
      tstHistory: [for (var i = 0; i < 20; i++) 400.0 + (i % 6) * 7],
      deviceFamily: family,
    ).toJson(),
  );
}

Map<String, dynamic> _scalars(Map<String, dynamic> b) =>
    (b['scalars'] as Map).cast<String, dynamic>();

void main() {
  test('only a verified family carries a skin-temperature channel', () {
    expect(hasVerifiedSkinTemp('gen5'), isTrue);
    expect(hasVerifiedSkinTemp('gen4'), isFalse);
    expect(hasVerifiedSkinTemp(null), isFalse);
    expect(hasVerifiedSkinTemp('oura'), isFalse);
  });

  test('WHOOP 4.0 counts publish no temperature output', () {
    final s = _scalars(_bundle(family: 'gen4', tempCount: 3100));
    expect(s['skin_temp_adc'], isNull);
    expect(s['skin_temp_z'], isNull);
    expect(s['skin_temp_coverage_frac'], isNull);
    expect(s['skin_temp_settled_frac'], isNull);
  });

  test('changing only WHOOP 4.0 counts cannot move readiness', () {
    final cool = _scalars(_bundle(family: 'gen4', tempCount: 2500));
    final warm = _scalars(_bundle(family: 'gen4', tempCount: 9000));
    expect(cool['readiness'], warm['readiness']);
  });

  test('unknown family is treated like WHOOP 4.0', () {
    final s = _scalars(_bundle(family: null, tempCount: 3100));
    expect(s['skin_temp_adc'], isNull);
    expect(s['skin_temp_z'], isNull);
  });

  test('a verified family keeps its channel', () {
    final s = _scalars(_bundle(family: 'gen5', tempCount: 3350));
    expect(s['skin_temp_adc'], isNotNull);
  });

  group('cross-day detectors', () {
    Map<String, dynamic> day(int i, {String? family, num? z, num? adc}) => {
          'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}',
          'rhr': 55,
          'rmssd': 50,
          'resp_rate': 14.5,
          'device_family': family,
          'skin_temp_z': z,
          'skin_temp_adc': adc,
        };

    test('stored WHOOP 4.0 and imported values never reach them', () {
      // 25 calm nights, then two with a huge stored "temperature" z: the
      // old path flagged this as a sustained rise.
      final days = [
        for (var i = 0; i < 25; i++) day(i, family: 'gen4', z: 0.1, adc: 3000),
        day(25, family: 'gen4', z: 9, adc: 9000),
        // An imported WHOOP CSV day writes absolute °C under skin_temp_z and
        // has no device family.
        day(26, z: 37.4),
      ];
      final b = buildCrossDayBundle(days, const {'age': 23, 'sex': 'm'});
      final flag = (b['temp_illness'] as Map?)?.cast<String, dynamic>();
      expect(flag?['flag'], isNot('elevated'));
    });

    test('a verified family feeds the raw nightly mean, not a z-score', () {
      // Raw centi-°C means steady at 3350, then two clearly warmer nights.
      // The stored z is deliberately inconsistent garbage: if the detector
      // still read z it could not see this rise.
      final days = [
        for (var i = 0; i < 25; i++)
          day(i, family: 'gen5', z: 0.0, adc: 3350 + (i % 3)),
        day(25, family: 'gen5', z: 0.0, adc: 3450),
        day(26, family: 'gen5', z: 0.0, adc: 3460),
      ];
      final b = buildCrossDayBundle(days, const {'age': 23, 'sex': 'm'});
      final flag = (b['temp_illness'] as Map?)?.cast<String, dynamic>();
      expect(flag?['flag'], 'elevated');
    });
  });
}
