// `kGaitStepTypeKeys` pinned against the activity catalogue.
//
// This test exists because of `kRouteTypeKeys`: that set was hardcoded as
// {'run', 'cycle', 'walk', 'hike'} while the catalogue's `typeKey` is
// `name.toLowerCase().replaceAll(' ', '_')`, so the app stored 'running',
// 'cycling', 'walking', 'hiking'. Zero overlap. No activity ever matched, so no
// route was ever recorded, for every user, silently.
//
// A stale gait set fails the same way and worse: an orphan key means the gate
// never opens (the strap counts no steps during any walk), and a MISSING key
// means it never closes (a rowing session banks arm swing as strides — the
// +199.5% over-count OXWALK_VALIDATION measured). Both directions are pinned.
//
// The catalogue carries no gait flag to derive from, and neither `Track` nor
// `gps` is a substitute — Track.distance holds Rowing and Swimming, gps: true
// holds Cycling and Kayaking. So the set is explicit and this test is what keeps
// it honest.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/live_step_runs.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';

void main() {
  final catalogueKeys = {for (final a in allActivities) a.typeKey};

  // THE PIN THAT MATTERS, and the one this test did not have at first.
  //
  // The catalogue now carries `gait: true`, so the set can be DERIVED from it
  // in both directions instead of hand-listed. Before, 55 of the 79 activities
  // were asserted by nobody: adding a gait activity and forgetting the set
  // would have banked no steps for it, silently, forever — which is exactly
  // the shape of the kRouteTypeKeys bug (a stale {'run','cycle','walk','hike'}
  // against a catalogue emitting 'running'/'walking', so no map was ever
  // recorded for anyone). Derived, that failure is a red test instead.
  final catalogueGait = {
    for (final a in allActivities)
      if (a.gait) a.typeKey,
  };

  test('every gait: true activity in the catalogue is counted', () {
    final missing = catalogueGait.difference(kGaitStepTypeKeys);
    expect(missing, isEmpty,
        reason: 'the catalogue marks these gait but the strap would count no '
            'steps for them: $missing');
  });

  test('nothing is counted that the catalogue does not call gait', () {
    final extra = kGaitStepTypeKeys.difference(catalogueGait);
    expect(extra, isEmpty,
        reason: 'these would bank strap steps without the catalogue agreeing '
            'they are locomotion on foot: $extra');
  });

  test('no activity is gait and cycling at once', () {
    // Cycling records a route and takes no steps; a treadmill takes steps and
    // records nothing. If the two flags ever agree on an entry, one is wrong.
    for (final a in allActivities) {
      if (a.gait && a.typeKey.contains('cycl')) {
        fail('${a.name} is flagged gait — pedalling is not stepping');
      }
    }
  });

  test('no gait key is one the catalogue cannot produce', () {
    final orphans = kGaitStepTypeKeys.difference(catalogueKeys);
    expect(
      orphans,
      isEmpty,
      reason:
          'these keys match no activity, so the gate would never open '
          'for them: $orphans — the exact shape of the kRouteTypeKeys bug',
    );
  });

  test('the arm-work activities are all OUT', () {
    // Not an exhaustive complement — a new catalogue entry must not silently
    // start counting, but it must not silently be forced out either. These are
    // the named failure cases: rhythmic arm motion at gait cadence with no
    // strides under it.
    for (final k in const [
      'rowing',
      'boxing',
      'martial_arts',
      'elliptical',
      'weight_training',
      'powerlifting',
      'kettlebell',
      'crossfit',
      'hiit',
      'circuit_training',
      'swimming',
      'cycling',
      'indoor_bike',
      'jump_rope',
      'housework',
      'gardening',
      'diy',
    ]) {
      expect(catalogueKeys, contains(k), reason: 'stale test, not stale code');
      expect(isGaitStepType(k), isFalse, reason: '$k is not gait');
    }
  });

  test('the gait activities are all IN, and are real catalogue entries', () {
    for (final k in const [
      'walking',
      'running',
      'trail_running',
      'hiking',
      'dog_walking',
      'treadmill',
      'cross_country',
    ]) {
      expect(catalogueKeys, contains(k), reason: 'stale test, not stale code');
      expect(isGaitStepType(k), isTrue);
    }
  });

  test(
    'an unknown stored type does not count, and neither does no session',
    () {
      // `sessions.type` is free-form TEXT and imports write into it.
      expect(isGaitStepType('walk'), isFalse);
      expect(isGaitStepType('some_imported_thing'), isFalse);
      expect(isGaitStepType(null), isFalse);
    },
  );
}
