// tap_router.dart — PURE mapping from a notification's deep-link route string
// to what the app should do with it: which shell tab to land on, and (new)
// which sub-screen to push on top. AppState feeds taps through here; the shell
// consumes both requests. Unknown routes fall back to Today (never crash on a
// stale payload from an old build).

/// Sub-screen deep links (notification payloads). The 5 tab routes
/// (/today /sleep /heart /body /workouts) stay as they were.
const String kRouteAiMorning = '/ai/morning';
const String kRouteAiEvening = '/ai/evening';
const String kRouteJournalCompose = '/journal/compose';
const String kRouteBreathing = '/breathing';

/// "Did you work out?" auto-detect notification. Lands on the Workouts tab and
/// pushes a focused review of the detected activity (log or adjust) — the plain
/// `/workouts` route only selected the tab, leaving the suggestion buried in the
/// history list (issue #113).
const String kRouteWorkoutSuggestion = '/workouts/suggestion';

/// Emitted by the battery forecast and the device alerts. Profile is reached
/// from the Home avatar rather than a tab of its own, so the base is Home and
/// `screenForRoute` pushes the profile on top of it.
const String kRouteProfile = '/profile';

/// Emitted by the weekly recap. There is no recap SCREEN, so this resolves to
/// the Health domain and pushes nothing — `screenForRoute` returns null for it
/// deliberately. It still has to be listed here, because a route absent from
/// this table produces no screen request at all and the shell then falls back
/// to the tab index, which is Home. That is how both of these used to land on
/// Home while `domainForRoute` claimed otherwise.
const String kRouteRecap = '/recap';

class TapTarget {
  /// Shell tab index to land on (always valid; unknown → 0 = Today).
  final int tab;

  /// When non-null, a sub-screen route the shell should push on top of the tab
  /// (one of the kRoute* consts above).
  final String? screen;

  const TapTarget(this.tab, [this.screen]);
}

const Map<String, int> _tabRoutes = {
  '/today': 0,
  '/sleep': 1,
  '/heart': 2,
  '/body': 3,
  '/workouts': 4,
};

// Sub-screen routes → the shell tab they sit on top of. Most briefing/journal
// deep links live over Today (0); the detected-workout review sits over the
// Workouts tab (4) so the tab underneath is the natural place to land on close.
//
// /profile and /recap were BOTH being emitted with neither table knowing them,
// so resolveTapRoute fell through to Today and every band-battery alert landed
// on the home screen — three taps from the battery it was about. The
// destinations exist in app.dart; this is the half that was missing.
const Map<String, int> _screenRoutes = {
  kRouteAiMorning: 0,
  kRouteAiEvening: 0,
  kRouteJournalCompose: 0,
  kRouteBreathing: 0,
  kRouteWorkoutSuggestion: 4,
  kRouteProfile: 0,
  kRouteRecap: 1, // 1|2|3 all fold into Health — see domainForTab
};

TapTarget resolveTapRoute(String route) {
  final tab = _tabRoutes[route];
  if (tab != null) return TapTarget(tab);
  final base = _screenRoutes[route];
  if (base != null) return TapTarget(base, route);
  return const TapTarget(0); // unknown payload from an older build → Today
}
