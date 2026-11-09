import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_companion/compute/input_reuse.dart';
import 'package:whoop_companion/compute/onehz_pipeline.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';

Map<String, dynamic> _input() {
  final start = DateTime(2026, 9, 20, 23).millisecondsSinceEpoch ~/ 1000;
  final rr = [for (var i = 0; i < 1200; i++) 950 + 30 * math.sin(i * .4)];
  var at = start * 1000.0;
  final times = <double>[];
  for (final r in rr) {
    at += r;
    times.add(at);
  }
  return DayBundleInput(
    date: '2026-09-21',
    dayTsSec: [start + 3600, start + 3601],
    dayHr: [80, 81],
    sleepTsSec: [for (var i = 0; i < 1200; i++) start + i],
    sleepHr: List.filled(1200, 55),
    sleepRrTsMs: times,
    sleepRrMs: rr,
    sleepSkinTemp: List.filled(1200, 2000),
    sleepJson: {'tst_sec': 1200, 'in_bed_sec': 1200, 'confidence': .8},
    hypnoStages: List.filled(1200, 'light'),
    sleepOnsetSec: start,
    sleepOffsetSec: start + 1200,
    profile: {'age': 30, 'sex': 'm', 'weight_kg': 80.0, 'height_cm': 180.0},
    deviceFamily: 'gen4',
  ).toJson();
}

void main() {
  test('cancelled worker cannot publish changed reuse state', () async {
    final cache = InputReuse(91);
    cache.get<int>('completed', 'old', () => 7);
    final worker = runCancellableIsolate(() async {
      cache.get<int>('completed', 'new', () => 9);
      await Future<void>.delayed(const Duration(seconds: 5));
      return cache;
    }, const Duration(seconds: 10));
    final checked = expectLater(worker, throwsA(isA<DeriveCancelled>()));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    DeriveStop.request('test background expiration');
    await checked;
    expect(cache.get<int>('completed', 'old', () => 99), 7);
    expect(cache.misses, 1);
  });
  test(
    'off-wrist silence is not a failed link; unknown/on wrist still recover',
    () {
      for (final wearing in <bool?>[null, true, false]) {
        expect(
          shouldReconnectForSilence(
            silence: const Duration(minutes: 5),
            fuseSeconds: 120,
            onWrist: wearing,
          ),
          wearing != false,
        );
        expect(
          isLinkStale(const Duration(minutes: 5), onWrist: wearing),
          wearing != false,
        );
      }
      expect(
        shouldReconnectForSilence(
          silence: const Duration(seconds: 120),
          fuseSeconds: 120,
          onWrist: true,
        ),
        isFalse,
      );
      // B88-05: off-wrist is not "never" — a link quiet past two missed slow
      // battery polls is dead and is bounced.
      const dead = Duration(seconds: kLinkFreshnessOffWristSeconds + 1);
      expect(isLinkStale(dead, onWrist: false), isTrue);
      expect(
        shouldReconnectForSilence(
          silence: dead,
          fuseSeconds: 120,
          onWrist: false,
          offWristFuseSeconds: kLinkFreshnessOffWristSeconds,
        ),
        isTrue,
      );
    },
  );
  test(
    'wear evidence is link scoped and older/future/invalid replay cannot win',
    () {
      const now = 1790000000;
      final wear = LinkWearEvidence(sinceSec: now);
      expect(wear.onWrist, isNull);
      expect(wear.absorb(false, now - 3600, nowSec: now), isFalse);
      expect(wear.absorb(false, now + 3600, nowSec: now), isFalse);
      expect(wear.onWrist, isNull);
      expect(wear.absorb(false, now, nowSec: now), isTrue);
      expect(wear.absorb(true, now - 30, nowSec: now), isFalse);
      expect(wear.absorb(true, 0, nowSec: now), isFalse);
      expect(wear.absorb(true, now + 86400 * 30, nowSec: now), isFalse);
      expect(wear.onWrist, isFalse);
      expect(wear.absorb(true, now + 1, nowSec: now + 1), isTrue);
      expect(LinkWearEvidence(sinceSec: now + 1).onWrist, isNull);
    },
  );
  test(
    'reuse equals fresh output across isolates and reuses unchanged night with new daytime HR',
    () async {
      final input = _input();
      final cache = InputReuse(91);
      final first = await Isolate.run(
        () => (bundle: deriveDayBundle(input, reuse: cache), cache: cache),
      );
      final next = {
        ...input,
        'day_hr': [90, 92],
        'day_ts': [
          (input['day_ts'] as List).first,
          (input['day_ts'] as List).last,
        ],
      };
      final second = await Isolate.run(
        () => (
          bundle: deriveDayBundle(next, reuse: first.cache),
          cache: first.cache,
        ),
      );
      expect(jsonEncode(second.bundle), jsonEncode(deriveDayBundle(next)));
      expect(second.cache.hits, greaterThan(8));
      final changed = {
        ...next,
        'sleep_rr_ms': [...(next['sleep_rr_ms'] as List<double>)],
      };
      (changed['sleep_rr_ms'] as List<double>)[20] += 4;
      final third = deriveDayBundle(changed, reuse: second.cache);
      expect(jsonEncode(third), jsonEncode(deriveDayBundle(changed)));
      expect(second.cache.misses, greaterThan(first.cache.misses));
    },
  );
  test(
    'profile, baseline, temperature and window edits do not leave cached results stale',
    () {
      final input = _input(), cache = InputReuse(91);
      deriveDayBundle(input, reuse: cache);
      for (final change in <Map<String, dynamic>>[
        {
          'profile': {
            'age': 51,
            'sex': 'm',
            'height_cm': 180.0,
            'weight_kg': 95.0,
          },
        },
        {
          'rhr_history': [52.0, 53.0, 54.0],
          'ln_rmssd_history': [3.2, 3.3, 3.4],
        },
        {'sleep_skin_temp': List.filled(1200, 2200)},
        {'sleep_offset_sec': (input['sleep_offset_sec'] as int) - 120},
        {'hypno_stages': List.filled(1200, 'rem')},
        {
          'step_spans': [
            [1790000000, 1790000060, 100],
          ],
        },
      ]) {
        final edited = {...input, ...change};
        expect(
          jsonEncode(deriveDayBundle(edited, reuse: cache)),
          jsonEncode(deriveDayBundle(edited)),
        );
      }
    },
  );
  test('failed calculation never records a successful reuse entry', () {
    final cache = InputReuse(91), stamp = 'exact';
    expect(
      () => cache.get<int>('broken', stamp, () => throw StateError('failed')),
      throwsStateError,
    );
    expect(cache.get<int>('broken', stamp, () => 42), 42);
    expect(cache.misses, 1);
    expect(InputReuse(92).stamp([1, 2]), isNot(cache.stamp([1, 2])));
  });
}
