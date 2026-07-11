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

  test('an unknown/stale route falls back to Today, never crashes', () {
    final t = resolveTapRoute('/recap');
    expect(t.tab, 0);
    expect(t.screen, isNull);
  });
}
