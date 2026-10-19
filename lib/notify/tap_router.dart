// tap_router.dart — PURE mapping from a notification's deep-link route string
// to what the app should do with it: which shell tab to land on, and (new)
// which sub-screen to push on top. AppState feeds taps through here; the shell
// consumes both requests. Unknown routes fall back to Today (never crash on a
// stale payload from an old build).

/// Sub-screen deep links (notification payloads). The 5 tab routes
/// (/today /sleep /heart /body /workouts) stay as they were.
/// "Did you work out?" auto-detect notification. Lands on the Workouts tab and
/// pushes a focused review of the detected activity (log or adjust) — the plain
/// `/workouts` route only selected the tab, leaving the suggestion buried in the
/// history list (issue #113).
///
/// Carries the bout it is about as `?id=<workout_suggestions.id>` — see
/// [workoutSuggestionRoute]. The bare path still resolves (older payloads, and
/// anything that just wants the review screen).
const String kRouteWorkoutSuggestion = '/workouts/suggestion';

/// "Your recovery is ready" — the morning recovery note. A DEDICATED PATH:
/// the recovery channel was where dead nudges went (`classOf` dropped all of it), so re-opening the CHANNEL would
/// resurrect them; keying on this route sanctions exactly one event. Its off
/// switch is NotificationPrefs.recoveryEnabled (the retained pref for that
/// channel). Lands on Home/Today, where the recovery ring lives.
const String kRouteRecovery = '/today/recovery';

/// The deep link for ONE detected bout. The id is the `workout_suggestions`
/// row's, so the screen can open on that bout rather than a list the user has
/// to find it in.
String workoutSuggestionRoute(String id) =>
    Uri(path: kRouteWorkoutSuggestion, queryParameters: {'id': id}).toString();

/// The forgotten-workout nudge ("Still working out?" — see
/// `WorkoutIdleWatch`). Lands on the Workouts tab: the live session bar and
/// its finish control are what the notification is about. A dedicated path
/// rather than the bare `/workouts` tab route, because `classOf`'s sanction
/// for it is route-keyed and the tab route must not open the
/// reminders-at-normal pair for everything that names it.
const String kRouteWorkoutIdle = '/workouts/idle';

/// A deep link's path, without the `?id=` a route may carry.
///
/// EVERY route comparison goes through this. The tables below, `classOf`,
/// `shouldFireOs`'s auto-detect switch and app.dart's two switches all match on
/// route EQUALITY, so an id-carrying payload silently misses all of them —
/// which for the gate means the off switch stops working.
String routePath(String route) => Uri.tryParse(route)?.path ?? route;

/// The bout/record id a deep link carries, or null when it carries none.
String? routeId(String route) => Uri.tryParse(route)?.queryParameters['id'];

String? routeDay(String route) {
  final day = Uri.tryParse(route)?.queryParameters['day'];
  final d = DateTime.tryParse(day ?? '');
  return day != null &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) &&
          d != null &&
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' ==
              day
      ? day
      : null;
}

String datedRoute(String route, String? day, {String? id}) {
  final uri = Uri.tryParse(route);
  if (uri == null) return route;
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          if (day != null) 'day': day,
          if (id != null) 'id': id,
        },
      )
      .toString();
}

/// Pushups reminders and the 9:00 invitation (build 86). Lands on Train with
/// the Pushups screen on top; Done and Pause on the notification never open it.
const String kRoutePushups = '/workouts/pushups';

/// Emitted by the battery forecast and the device alerts. Profile is reached
/// from the Home avatar rather than a tab of its own, so the base is Home and
/// `screenForRoute` pushes the profile on top of it.
const String kRouteProfile = '/profile';

/// Emitted by the weekly recap. It used to resolve to the Health domain and
/// push nothing, because there was no recap screen to push — `screenForRoute`
/// returned null for it deliberately. There is one now (`WhatChangedScreen`),
/// so the notification finally lands on the findings it is about.
///
/// It still has to be listed here, because a route absent from this table
/// produces no screen request at all and the shell then falls back to the tab
/// index, which is Home. That is how both of these used to land on Home while
/// `domainForRoute` claimed otherwise.
const String kRouteRecap = '/recap';

/// The signing-expiry warnings land on the Status screen, which shows the
/// installed profile's live expiry, the last band data and the last backup.
const String kRouteStatus = '/status';

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
  // Build 89: the evening food question lands on Food (`domainForTab` 6).
  '/food': 6,
  // The forgotten-workout nudge. The Workouts tab IS its destination — the
  // live session bar with the finish control is pinned to the shell there and
  // `screenForRoute` has nothing to push — so it belongs in the tab table,
  // not `_screenRoutes`. (It keeps its own path because `classOf`'s sanction
  // is route-keyed — see kRouteWorkoutIdle above.)
  kRouteWorkoutIdle: 4,
};

// Sub-screen routes → the shell tab they sit on top of. The detected-workout
// review sits over the Workouts tab (4) so the tab underneath is the natural
// place to land on close.
//
// /profile and /recap were BOTH being emitted with neither table knowing them,
// so resolveTapRoute fell through to Today and every band-battery alert landed
// on the home screen — three taps from the battery it was about. The
// destinations exist in app.dart; this is the half that was missing.
const Map<String, int> _screenRoutes = {
  kRouteWorkoutSuggestion: 4,
  kRouteProfile: 0,
  kRouteRecap: 1, // 1|2|3 all fold into Health — see domainForTab
  kRouteStatus: 0,
  kRouteRecovery: 0,
  kRouteWorkoutIdle: 4,
  kRoutePushups: 4,
  '/sleep': 0,
  '/heart': 1,
};

TapTarget resolveTapRoute(String route) {
  // Match on the PATH; hand the full route (id and all) back as the screen
  // request, so whatever the shell pushes still knows which bout it is about.
  final path = routePath(route);
  final base = _screenRoutes[path];
  if (base != null) return TapTarget(base, route);
  final tab = _tabRoutes[path];
  if (tab != null) return TapTarget(tab);
  return const TapTarget(0); // unknown payload from an older build → Today
}
