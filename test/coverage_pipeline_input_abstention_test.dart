// Short authored wake-only inputs to the existing approved pipeline.
// This verifies absence and transport, not a new calorie method or full night.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/onehz_pipeline.dart';

const start = 1760000040; // minute-aligned, independent of the host timezone
const profile = <String, dynamic>{
  'age': 30,
  'sex': 'm',
  'weight_kg': 70.0,
  'height_cm': 170.0,
  'resting_hr': 55.0,
};
DayBundleInput input({
  Map<String, dynamic> person = profile,
  String? family = 'gen4',
  bool empty = false,
  bool steps = false,
}) => DayBundleInput(
  date: '2025-10-09',
  dayTsSec: empty ? [] : [for (var i = 0; i < 120; i++) start + i],
  dayHr: empty ? [] : List<int>.filled(120, 100),
  sleepTsSec: const [],
  sleepHr: const [],
  sleepRrTsMs: const [],
  sleepRrMs: const [],
  sleepSkinTemp: const [],
  sleepJson: const {},
  hypnoStages: const [],
  sleepOnsetSec: 0,
  sleepOffsetSec: 0,
  profile: person,
  deviceFamily: family,
  stepSpans: steps
      ? [
          [start, start + 120, 200],
        ]
      : const [],
);

void main() {
  for (final missing in ['age', 'sex', 'weight_kg', 'height_cm']) {
    test(
      'missing $missing stays absent with its own reason, without inventing sleep or readiness',
      () {
        final p = {...profile}..remove(missing);
        final before = jsonEncode(p);
        final b = deriveDayBundle(input(person: p).toJson());
        final notes = b['absent_notes'] as Map;
        final scalars = b['scalars'] as Map;
        expect(b['calories'], isNull);
        expect(scalars['calories'], isNull);
        expect(notes['calories'], 'need_input:name=$missing');
        expect(notes['calories_total'], notes['calories']);
        expect(scalars['readiness'], isNull);
        expect(jsonEncode(p), before);
        if (missing == 'sex' || missing == 'resting_hr') {
          expect(scalars['strain'], isNull);
          expect(notes['strain'], 'need_input:name=$missing');
        }
      },
    );
  }

  test(
    'unstamped measuring family retains the age estimate and explicit provenance',
    () {
      final b = deriveDayBundle(input(family: null).toJson());
      expect(b['device_family'], isNull);
      expect(b['max_hr_used'], 187);
      expect(b['zone_source'], 'tanaka');
      expect(b['calories'], isA<num>());
      expect((b['absent_notes'] as Map).containsKey('calories'), isFalse);
      expect((b['scalars'] as Map)['readiness'], isNull);
    },
  );

  test(
    'no wake samples explain missing activity instead of billing a basal or active day',
    () {
      final b = deriveDayBundle(input(empty: true).toJson());
      final notes = b['absent_notes'] as Map;
      expect(notes['calories'], 'need_input:name=wake_hr');
      expect(notes['strain'], 'need_input:name=wake_hr');
      expect(b['calories'], isNull);
      expect((b['scalars'] as Map)['readiness'], isNull);
    },
  );

  test(
    'existing measured-cadence path produces finite activity without modifying its input spans',
    () {
      final d = input(steps: true);
      final before = jsonEncode(d.toJson());
      final b = deriveDayBundle(d.toJson());
      expect(b['calories'], isA<num>());
      expect((b['calories'] as num).isFinite, isTrue);
      expect(b['calories'], greaterThanOrEqualTo(0));
      expect((b['absent_notes'] as Map).containsKey('calories'), isFalse);
      expect(jsonEncode(d.toJson()), before);
      expect(
        (b['scalars'] as Map)['readiness'],
        isNull,
        reason: 'Two awake minutes are not a scored night',
      );
    },
  );

  test(
    'untyped JSON numeric arrays cross the isolate seam as independent double copies',
    () {
      final raw = input().toJson();
      raw['day_rr_ms'] = <num>[800, 801.5];
      raw['day_rr_ts_ms'] = <num>[1000, 1801.5];
      raw['sleep_rr_ms'] = <num>[900, 901];
      raw['ln_rmssd_history'] = <num>[3, 3.5];
      final decoded = DayBundleInput.fromJson(raw);
      expect(decoded.dayRrMs, [800.0, 801.5]);
      expect(decoded.sleepRrMs, [900.0, 901.0]);
      expect(decoded.lnRmssdHistory, [3.0, 3.5]);
      (raw['day_rr_ms'] as List)[0] = 999;
      expect(decoded.dayRrMs.first, 800);
      decoded.dayRrMs[1] = 700;
      expect((raw['day_rr_ms'] as List)[1], 801.5);
    },
  );
}
