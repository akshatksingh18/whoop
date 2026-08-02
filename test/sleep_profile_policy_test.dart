// Regression coverage for the rolling sleep-profile fold rules.
//
// The motivating defect, from a real user export: `sleep_user_profile` held
// `"nights": 1348` against 12 days of data, because the EWMA fold ran on every
// staging pass rather than once per day. That saturated `personalWeight` at its
// 0.5 cap immediately and collapsed the EWMA onto the most recently re-derived
// day. Replaying that profile over the same 11 nights moved wake 4.3% → 36.4%
// and deep 1.9% → 0.0% on the worst night.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_profile_policy.dart';

String _payload({List<String>? foldedDays, int nights = 0}) => jsonEncode({
      'nights': nights,
      'hr_sleep_median': 52.5,
      SleepProfilePolicy.foldedDaysKey: ?foldedDays,
    });

void main() {
  group('fold idempotency (the nights:1348 bug)', () {
    test('a day already folded is never folded again', () {
      final folded = SleepProfilePolicy.foldedDays(
          _payload(foldedDays: ['2026-07-30'], nights: 1));
      expect(
        SleepProfilePolicy.shouldFold(
            alreadyFolded: folded, dayId: '2026-07-30', hasOverride: false),
        isFalse,
      );
    });

    test('a day not yet folded is folded once', () {
      final folded = SleepProfilePolicy.foldedDays(
          _payload(foldedDays: ['2026-07-30'], nights: 1));
      expect(
        SleepProfilePolicy.shouldFold(
            alreadyFolded: folded, dayId: '2026-07-31', hasOverride: false),
        isTrue,
      );
    });

    test('repeated staging passes over the same days cannot inflate nights',
        () {
      // Simulate what actually happened: 12 real days, re-derived 100x each.
      var folded = <String>{};
      var foldCount = 0;
      final days = [for (var d = 20; d < 32; d++) '2026-07-$d'];
      for (var pass = 0; pass < 100; pass++) {
        for (final day in days) {
          if (SleepProfilePolicy.shouldFold(
              alreadyFolded: folded, dayId: day, hasOverride: false)) {
            foldCount++;
            folded = {...SleepProfilePolicy.appendFoldedDay(folded, day)};
          }
        }
      }
      expect(foldCount, days.length, reason: 'one fold per distinct day');
      expect(folded.length, days.length);
    });

    test('an override night never folds — the window is asserted, not measured',
        () {
      expect(
        SleepProfilePolicy.shouldFold(
            alreadyFolded: const {}, dayId: '2026-07-31', hasOverride: true),
        isFalse,
      );
    });
  });

  group('minimum-nights warm-up gate', () {
    test('withholds the profile below the floor', () {
      expect(SleepProfilePolicy.shouldBlend(0), isFalse);
      expect(SleepProfilePolicy.shouldBlend(1), isFalse);
      expect(SleepProfilePolicy.shouldBlend(2), isFalse);
    });

    test('applies the profile at and above the floor', () {
      expect(SleepProfilePolicy.shouldBlend(3), isTrue);
      expect(SleepProfilePolicy.shouldBlend(30), isTrue);
    });

    test('a null nights count never blends', () {
      expect(SleepProfilePolicy.shouldBlend(null), isFalse);
    });
  });

  group('legacy payloads are discarded, not trusted', () {
    test('a pre-tracking profile is legacy and yields a cold start', () {
      final legacy = _payload(nights: 1348); // no folded_days key
      expect(SleepProfilePolicy.isLegacy(legacy), isTrue);
      expect(SleepProfilePolicy.usableProfileJson(legacy), isNull);
    });

    test('a tracked profile survives unchanged', () {
      final tracked = _payload(foldedDays: ['2026-07-30'], nights: 1);
      expect(SleepProfilePolicy.isLegacy(tracked), isFalse);
      expect(SleepProfilePolicy.usableProfileJson(tracked), tracked);
    });

    test('null and corrupt payloads are cold starts but not "legacy"', () {
      for (final bad in [null, '', 'not json', '[1,2,3]']) {
        expect(SleepProfilePolicy.usableProfileJson(bad), isNull);
        expect(SleepProfilePolicy.isLegacy(bad), isFalse);
        expect(SleepProfilePolicy.foldedDays(bad), isEmpty);
      }
    });

    test('a tracked-but-empty profile is usable (mid-rebuild, not legacy)', () {
      final rebuilding = _payload(foldedDays: const [], nights: 0);
      expect(SleepProfilePolicy.isLegacy(rebuilding), isFalse);
      expect(SleepProfilePolicy.usableProfileJson(rebuilding), rebuilding);
    });
  });

  group('profile lock (concurrent-day race)', () {
    test('serialises read-modify-write so no fold is clobbered', () async {
      // Model the real shape: N days derive concurrently, each reads the
      // shared profile, awaits (staging), then writes it back. Without the
      // lock the later writer overwrites the earlier one's folded_days.
      var profile = jsonEncode({'nights': 0, 'folded_days': <String>[]});
      Future<void> foldDay(String day) =>
          SleepProfilePolicy.withProfileLock(() async {
            final days = SleepProfilePolicy.foldedDays(profile);
            if (!SleepProfilePolicy.shouldFold(
                alreadyFolded: days, dayId: day, hasOverride: false)) {
              return;
            }
            await Future<void>.delayed(Duration.zero); // yield mid-section
            final n = (jsonDecode(profile) as Map)['nights'] as int;
            profile = jsonEncode(SleepProfilePolicy.withFoldedDays(
                {'nights': n + 1}, days, day));
          });

      final days = ['2026-07-28', '2026-07-29', '2026-07-30', '2026-07-31'];
      await Future.wait(days.map(foldDay));

      final decoded = jsonDecode(profile) as Map;
      expect(decoded['nights'], days.length,
          reason: 'every concurrent fold must be counted exactly once');
      expect(
        (decoded[SleepProfilePolicy.foldedDaysKey] as List).cast<String>(),
        days,
        reason: 'no day_id may be lost to a clobbering write',
      );
    });

    test('a day already folded by another lane is skipped, not double-counted',
        () async {
      var profile =
          jsonEncode({'nights': 1, 'folded_days': const ['2026-07-30']});
      var folds = 0;
      Future<void> foldDay(String day) =>
          SleepProfilePolicy.withProfileLock(() async {
            final days = SleepProfilePolicy.foldedDays(profile);
            if (!SleepProfilePolicy.shouldFold(
                alreadyFolded: days, dayId: day, hasOverride: false)) {
              return;
            }
            await Future<void>.delayed(Duration.zero);
            folds++;
            profile = jsonEncode(
                SleepProfilePolicy.withFoldedDays({'nights': 99}, days, day));
          });

      await Future.wait([foldDay('2026-07-30'), foldDay('2026-07-30')]);
      expect(folds, 0, reason: 'already folded, by either lane');
    });

    test('a throwing action releases the lock', () async {
      await expectLater(
        SleepProfilePolicy.withProfileLock<void>(
            () async => throw StateError('boom')),
        throwsStateError,
      );
      var ran = false;
      await SleepProfilePolicy.withProfileLock(() async => ran = true);
      expect(ran, isTrue, reason: 'lock must not deadlock after a failure');
    });
  });

  group('folded-day bookkeeping', () {
    test('append is sorted and de-duplicated', () {
      final out = SleepProfilePolicy.appendFoldedDay(
          {'2026-07-31', '2026-07-29'}, '2026-07-30');
      expect(out, ['2026-07-29', '2026-07-30', '2026-07-31']);
      expect(SleepProfilePolicy.appendFoldedDay(out.toSet(), '2026-07-30'),
          hasLength(3));
    });

    test('the set is capped, evicting the oldest', () {
      var days = <String>{};
      for (var i = 0; i < SleepProfilePolicy.maxFoldedDays + 50; i++) {
        days = {
          ...SleepProfilePolicy.appendFoldedDay(
              days, '2020-01-${i.toString().padLeft(5, '0')}')
        };
      }
      expect(days, hasLength(SleepProfilePolicy.maxFoldedDays));
      expect(days.contains('2020-01-00000'), isFalse, reason: 'oldest evicted');
      expect(days.contains('2020-01-00449'), isTrue, reason: 'newest kept');
    });

    test('withFoldedDays stamps the key without disturbing profile fields', () {
      final stamped = SleepProfilePolicy.withFoldedDays(
        {'nights': 4, 'hr_sleep_median': 52.5},
        {'2026-07-30'},
        '2026-07-31',
      );
      expect(stamped['nights'], 4);
      expect(stamped['hr_sleep_median'], 52.5);
      expect(stamped[SleepProfilePolicy.foldedDaysKey],
          ['2026-07-30', '2026-07-31']);
    });

    test('round-trips through JSON so the next pass reads what we wrote', () {
      final stamped = SleepProfilePolicy.withFoldedDays(
          {'nights': 1}, const {}, '2026-07-31');
      final reread = SleepProfilePolicy.foldedDays(jsonEncode(stamped));
      expect(reread, {'2026-07-31'});
      expect(
        SleepProfilePolicy.shouldFold(
            alreadyFolded: reread, dayId: '2026-07-31', hasOverride: false),
        isFalse,
        reason: 'the day we just folded must not fold again next pass',
      );
    });
  });
}
