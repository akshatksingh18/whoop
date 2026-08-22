// Tests for the battery-audit PR's pure policy surfaces that shipped without
// any: DeriveDebouncer's background tier (the biggest behaviour change in the
// PR — one pass per 45-min maxWait instead of per 5-min fresh window),
// isLinkStale's no-stream bar (the keep-alive poll swap's correctness
// condition), and the widget snapshot fingerprint (which already shipped one
// silent-freeze bug inside this PR — a missing key — that a reviewer caught
// rather than a test).

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/sync/sync_policy.dart';
import 'package:openstrap_edge/widget/widget_service.dart';

DeriveDebouncer _deb() => const DeriveDebouncer();

void main() {
  group('DeriveDebouncer.nextCheckDelay — background tier', () {
    test('background beats fresh/stale whenever isBackgrounded', () {
      // Fresh data + backgrounded: the foreground human argument is gone and
      // widget/HC freshness tolerates ~45 min, so this must be the SLOW tier,
      // not fresh's 1-min quiet / 5-min max.
      final d = _deb().nextCheckDelay(
        sinceLastRecord: const Duration(seconds: 5),
        sinceFirstPending: const Duration(seconds: 5),
        dataStaleness: const Duration(minutes: 1),
        isBackgrounded: true,
      );
      // quiet(20m) - 5s sinceLast vs maxWait(45m) - 5s pending → min ≈ 19m55s
      expect(d, const Duration(minutes: 19, seconds: 55));
    });

    test('background maxWait caps at 45 min of pending work', () {
      final d = _deb().nextCheckDelay(
        sinceLastRecord: const Duration(minutes: 2),
        sinceFirstPending: const Duration(minutes: 44),
        dataStaleness: const Duration(minutes: 3),
        isBackgrounded: true,
      );
      expect(d, const Duration(minutes: 1),
          reason: 'maxWait 45m - 44m pending = 1m');
    });

    test('foreground still wins over background when both set', () {
      final d = _deb().nextCheckDelay(
        sinceLastRecord: const Duration(seconds: 2),
        sinceFirstPending: const Duration(seconds: 2),
        dataStaleness: const Duration(hours: 5),
        isForeground: true,
        isBackgrounded: false,
      );
      expect(d, lessThan(const Duration(seconds: 15)),
          reason: 'a human is staring at the screen');
    });

    test('never returns less than the 1 s floor', () {
      final d = _deb().nextCheckDelay(
        sinceLastRecord: const Duration(minutes: 30),
        sinceFirstPending: const Duration(minutes: 50),
        dataStaleness: const Duration(minutes: 31),
        isBackgrounded: true,
      );
      expect(d, equals(const Duration(seconds: 1)));
    });
  });

  group('isLinkStale no-stream bar vs the keep-alive poll cadence', () {
    test('one dropped poll reply does NOT trip the bar', () {
      // Poll forced after 45 s silence on ~30 s ticks; a dropped REPLY is
      // retried within the next tick, so a healthy quiet link shows ≤ ~80 s.
      const bar = Duration(seconds: kLinkFreshnessNoStreamSeconds);
      const worstHealthyAfterOneDrop = Duration(seconds: 80);
      expect(worstHealthyAfterOneDrop < bar, isTrue);
      expect(isLinkStale(worstHealthyAfterOneDrop, liveStreamArmed: false),
          isFalse);
    });

    test('two consecutive missed polls DO trip it', () {
      expect(isLinkStale(const Duration(seconds: kLinkFreshnessNoStreamSeconds),
          liveStreamArmed: false), isTrue);
    });

    test('streaming bar stays tighter than the fuse', () {
      expect(kLinkFreshnessSeconds, lessThan(kLivenessFuseSeconds));
      expect(isLinkStale(const Duration(seconds: 30)), isTrue);
      expect(isLinkStale(const Duration(seconds: 29)), isFalse);
    });
  });

  group('widget snapshot fingerprint', () {
    test('covers every key push writes', () {
      // The gate silently freezes any key absent from the fingerprint. This
      // assertion IS the review fix: #261 added ring_*/sleep_efficiency to
      // push() and the shipped fingerprint did not know. Keep in lockstep
      // with push().
      for (final key in [
        'statusDay',
        'has_data',
        'readiness',
        'readiness_tier',
        'readiness_band',
        'hrv',
        'hrv_baseline',
        'strain',
        'sleep_min',
        'sleep_need_min',
        'rhr',
        'sleep_efficiency',
        'overnight_why',
        'coach_line',
        'ring_recovery_state',
        'ring_recovery_value',
        'ring_recovery_sub',
        'ring_recovery_why',
        'ring_recovery_frac',
        'ring_strain_state',
        'ring_strain_frac',
        'ring_sleep_state',
        'ring_sleep_frac',
        // updated_at deliberately excluded: write-time metadata.
      ]) {
        if (key == 'updated_at') continue;
        expect(
          WidgetService.fingerprintKeyOrder,
          contains(key),
          reason: '$key is written by push() but not fingerprinted — '
              'it would freeze until the next real change',
        );
      }
      expect(WidgetService.fingerprintKeyOrder, isNot(contains('updated_at')));
    });
  });
}
