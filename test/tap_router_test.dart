// tap_router.dart — pure route resolution. Regression coverage for the new
// kRouteBreathing entry (Siri/Shortcuts "start breathing" App Intent).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/tap_router.dart';

void main() {
  test('tab routes land on their index with no sub-screen', () {
    expect(resolveTapRoute('/today').tab, 0);
    expect(resolveTapRoute('/today').screen, isNull);
    expect(resolveTapRoute('/sleep').tab, 1);
    expect(resolveTapRoute('/workouts').tab, 4);
  });

  test('kRouteBreathing resolves to Today tab + the breathing sub-screen', () {
    final t = resolveTapRoute(kRouteBreathing);
    expect(t.tab, 0);
    expect(t.screen, kRouteBreathing);
  });

  test('other sub-screen routes still resolve correctly', () {
    expect(resolveTapRoute(kRouteAiMorning).screen, kRouteAiMorning);
    expect(resolveTapRoute(kRouteAiEvening).screen, kRouteAiEvening);
    expect(resolveTapRoute(kRouteJournalCompose).screen, kRouteJournalCompose);
  });

  test(
      'kRouteWorkoutSuggestion lands on the Workouts tab + the suggestion '
      'sub-screen (issue #113)', () {
    final t = resolveTapRoute(kRouteWorkoutSuggestion);
    expect(t.tab, 4); // Workouts tab underneath
    expect(t.screen, kRouteWorkoutSuggestion); // focused log/adjust review
  });

  test('plain /workouts still resolves to the tab with no sub-screen', () {
    // The auto-detect notification now uses kRouteWorkoutSuggestion, but the
    // bare tab route must keep working for any other caller.
    final t = resolveTapRoute('/workouts');
    expect(t.tab, 4);
    expect(t.screen, isNull);
  });

  test('an unknown/stale route falls back to Today, never crashes', () {
    final t = resolveTapRoute('/nope/from/an/older/build');
    expect(t.tab, 0);
    expect(t.screen, isNull);
  });

  // Every route the app can still put in a notification payload, now that the
  // set is down to three classes. A route missing from the tables resolves to
  // TapTarget(0) with no screen request — indistinguishable from a stale
  // payload, and the reason a band-battery alert used to land on Home three
  // taps from the battery it was about.
  test('every route a notification can still carry resolves somewhere real',
      () {
    // The band's own failures — battery, charger, gone quiet.
    final profile = resolveTapRoute(kRouteProfile);
    expect(profile.screen, kRouteProfile,
        reason: 'without a screen request the shell only selects a tab');

    // The weekly lookback. No recap screen exists, so the screen request
    // resolves to null in app.dart — but the request itself is what carries it
    // to Health rather than Home.
    final recap = resolveTapRoute(kRouteRecap);
    expect(recap.screen, kRouteRecap);
    expect(recap.tab, isNot(0), reason: 'a week of data is not the Home tab');

    // The day's aggregated health exception, and the alarm.
    expect(resolveTapRoute('/heart').tab, 2);
    expect(resolveTapRoute('/today').tab, 0);
  });
}
