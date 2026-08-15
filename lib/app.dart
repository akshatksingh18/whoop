import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'coach/coach_config.dart';
import 'notify/notification_service.dart';
import 'notify/tap_router.dart';
import 'state/app_state.dart';
import 'state/prefs.dart';
import 'telemetry/telemetry_service.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_switcher.dart';
import 'ui2/activity/catalogue.dart';
import 'ui2/activity/live.dart';
import 'ui2/onboarding/pairing.dart';
import 'ui2/onboarding/profile_setup.dart';
import 'ui2/onboarding/splash.dart';
import 'ui2/onboarding/welcome.dart';
import 'ui2/profile/profile.dart';
import 'ui2/screens/calm_breathing.dart';
import 'ui2/screens/health_screen.dart';
import 'ui2/screens/home_screen.dart';
import 'ui2/screens/journal_compose.dart';
import 'ui2/screens/nutrition_screen.dart';
import 'ui2/screens/wellness_screen.dart';
import 'ui2/screens/workout_screen.dart';
import 'ui2/ui2.dart';

class OpenStrapApp extends StatefulWidget {
  const OpenStrapApp({super.key});
  @override
  State<OpenStrapApp> createState() => _OpenStrapAppState();
}

class _OpenStrapAppState extends State<OpenStrapApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hand the BYOK provider config to AppState (briefing generation + the
    // key-aware AI notification schedule live there).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().attachCoachConfig(context.read<CoachConfig>());

      final app = context.read<AppState>();
      if (app.isPaired) app.openSession();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Keep the app in sync with the OS when the user is on "System".
    context.read<ThemeController>().updatePlatformBrightness(
        WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    if (state == AppLifecycleState.resumed) {
      // The user may have flipped our notification switch either way in OS
      // Settings while we were backgrounded. Drop the cached authorization
      // decision so the next present/schedule re-reads reality — a denial used
      // to latch for the whole process, silencing every notification and
      // scheduled reminder until a full app restart.
      NotificationService.instance.invalidatePermissionCache();
      // A background relaunch while the phone was locked cannot read the
      // keychain, so the BYOK key can be missing from an otherwise healthy
      // process. Coming to the foreground means the phone is unlocked — take
      // the chance to read it. No-op unless a key is known to exist and is
      // currently unreadable.
      unawaited(context.read<CoachConfig>().refreshKeyOnResume());
      app.maybeFinishFromLiveActivity();
      unawaited(app.maybeStopBreathingFromLiveActivity());
      app.refreshAppStatus(); // re-check OTA + admin banner on every foreground
      app.runCadenceChecks(); // evening wind-down / weekly recap nudges (best-effort)
      // A Siri "start breathing" App Intent may have just foregrounded an
      // already-running process (openAppWhenRun doesn't guarantee a fresh
      // launch) — the constructor-time check alone would miss that case.
      unawaited(app.checkPendingSiriRoute());
      // Backups run on foreground, when due — there is no background scheduler
      // that works on both platforms, and a schedule that claims "daily" while
      // delivering whenever the OS feels like it is worse than one that is
      // honest about when it fires.
      unawaited(app.runBackupIfDue());
      if (app.isPaired) app.openSession();
    } else if (state == AppLifecycleState.paused) {
      // Backgrounded: hand the band to the iOS restore path so it can wake-and-drain
      // in the background (no-op on Android, where the foreground service holds it).
      app.pauseForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: 'OpenStrap',
      debugShowCheckedModeBanner: false,
      // The palette is the design system's, the CHOICE is still the user's.
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: theme.materialThemeMode,
      builder: (context, child) =>
          ThemeSwitchOverlay(key: themeSwitchKey, child: child!),
      navigatorObservers: [TelemetryNavigatorObserver()],
      home: const _Gate(),
    );
  }
}

// ══════════════════ THE ONBOARDING GATE ══════════════════

/// The gate, as a pure function of its inputs. Onboarding order bugs are
/// the ones users hit exactly once and never forgive, so this is testable
/// without a band, a database or a widget tree.
///
/// [AppRoute.pairing] short-circuits before AppState ever looks at the
/// profile, so a skipped pairing falls through to profile setup rather than
/// straight to the shell — we still want the four numbers.
///
/// [onboarded] is the difference between "has never had a band" and "has no
/// band right now". `AppState.route` only knows the second: a user who forgets
/// their strap after months of use goes `isPaired == false` →
/// [AppRoute.pairing], and `pairingSkipped` is false for anyone who actually
/// paired, so they landed in FIRST-RUN onboarding with all their data behind
/// it and "Skip for now" as the only way back. Onboarding happens once.
AppRoute resolveRoute(AppRoute route,
    {required bool pairingSkipped,
    required bool profileSeen,
    bool onboarded = false}) {
  var r = route;
  if (onboarded && (r == AppRoute.pairing || r == AppRoute.profile)) {
    return AppRoute.shell;
  }
  if (r == AppRoute.pairing && pairingSkipped) r = AppRoute.profile;
  if (r == AppRoute.profile && profileSeen) return AppRoute.shell;
  return r;
}

/// One-way latch: this install has reached the app itself at least once.
///
/// Kept here rather than on [OnboardingBypass] because it is not a bypass —
/// nothing was skipped. It is the record that onboarding HAPPENED, which is
/// the only thing that distinguishes a lost band from a first run.
const String _kOnboarded = 'onboard.completed';

bool get _onboarded => Prefs.getBool(_kOnboarded, false);
void _markOnboarded() {
  if (!_onboarded) Prefs.setBool(_kOnboarded, true);
}

/// Telemetry-only: the last AppRoute we logged, so the gate's build (which
/// also re-runs on a plain theme flip) doesn't double-log.
AppRoute? _telemetryLastRoute;

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    // SELECT, not watch: rebuild only when the ROUTE actually changes (rare) —
    // not on every ~1 Hz AppState tick (live HR, log lines). Watching the whole
    // AppState here used to repaint the entire home stack every second, which
    // starved the background BLE connection on long idle stretches.
    final raw = context.select<AppState, AppRoute>((a) => a.route);
    return ValueListenableBuilder<int>(
      valueListenable: OnboardingBypass.revision,
      builder: (context, _, _) {
        final route = resolveRoute(raw,
            pairingSkipped: OnboardingBypass.pairingSkipped,
            profileSeen: OnboardingBypass.profileSeen,
            onboarded: _onboarded);
        if (route != _telemetryLastRoute) {
          _telemetryLastRoute = route;
          TelemetryService.instance.setContext('app_route', route.name);
          TelemetryService.instance.breadcrumb('route: ${route.name}');
        }
        final Widget resolved = switch (route) {
          // Underlay while the boot splash covers the loading phase — and what
          // the user lands on if the splash's safety cap fires before init
          // completes.
          AppRoute.loading => const _Loading(),
          AppRoute.welcome => const WelcomeScreen(),
          AppRoute.pairing => PairingScreen(
              onSkip: () => OnboardingBypass.mark(OnboardingBypass.kPairing)),
          AppRoute.profile => ProfileSetupScreen(
              onDone: () => OnboardingBypass.mark(OnboardingBypass.kProfile)),
          AppRoute.shell => const _Shell(),
        };
        // Cold-start splash: covers the whole loading phase and cross-fades out
        // the instant AppState finishes initializing, even mid-play. Shown once
        // per launch; BootSplash latches itself off after.
        return BootSplash(ready: route != AppRoute.loading, child: resolved);
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(child: CircularProgressIndicator(color: p.on(C.green))),
    );
  }
}

// ══════════════════ THE SHELL ══════════════════

/// A notification's tab index → the domain that now owns that content.
///
/// The indices come from `tap_router.dart`, which still speaks the old
/// five-tab vocabulary (Today · Sleep · Heart · Body · Workouts). Sleep, Heart
/// and Body all folded into Health, so three of the five collapse onto one
/// destination. Payloads from older builds keep working, which is the whole
/// point — a notification is scheduled days before it is tapped.
ShellDomain domainForTab(int tab) => switch (tab) {
      1 || 2 || 3 => ShellDomain.health,
      4 => ShellDomain.workout,
      _ => ShellDomain.home,
    };

/// A deep-link sub-screen route → the domain it belongs to.
///
/// Every `kRoute*` in `tap_router.dart` is here, and unknown routes fall back
/// to Home rather than crashing a cold launch on a payload from an older
/// build.
ShellDomain domainForRoute(String route) => switch (route) {
      kRouteAiMorning || kRouteAiEvening => ShellDomain.home,
      kRouteJournalCompose || kRouteBreathing => ShellDomain.wellness,
      kRouteWorkoutSuggestion => ShellDomain.workout,
      // Literals, not constants: these two are emitted by the battery
      // forecast (`app_state.dart`) and the weekly recap
      // (`notification_center.dart`) and are not in `tap_router`'s tables yet,
      // so nothing declares them. The destinations exist here either way.
      kRouteProfile => ShellDomain.home,
      // No recap screen exists. Health is where a week of sleep, strain and
      // recovery actually lives, so it is the nearest true destination — but
      // the notification promises a REPORT, and until one is built the honest
      // fix is upstream, in what that notification claims.
      kRouteRecap => ShellDomain.health,
      _ => ShellDomain.home,
    };

// `/profile` and `/recap` are declared in `tap_router.dart` alongside every
// other deep link. They used to be private literals here, which is exactly why
// both landed on Home: absent from tap_router's table, they produced no screen
// request, so the shell fell back to the tab index and never consulted
// [domainForRoute] at all.

/// The focused screen a deep link pushes on top of its domain, when one
/// exists. Null means the domain itself is the destination.
///
/// Two routes resolve to null and should not: `/ai/*` (there is no briefing
/// surface, and no BYOK settings screen to configure one — the feature is
/// unreachable, so the reminder should be off rather than landing here) and
/// `/workouts/suggestion` ("Tap to log it" has nothing to tap through to —
/// nothing reads `workout_suggestions`). Both are recorded in the sweep; the
/// fix for each is to stop making the promise, not to route it somewhere
/// plausible.
Widget? screenForRoute(String route) => switch (route) {
      kRouteJournalCompose => const JournalCompose(),
      kRouteBreathing => const CalmBreathing(),
      // Battery, band and sources all live behind this one.
      kRouteProfile => const ProfileHome(),
      _ => null,
    };

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  /// Restore the last-selected tab so a relaunch lands where the user left off.
  late ShellDomain _domain = ShellDomain
      .values[Prefs.getInt(Prefs.shellTab, 0).clamp(0, ShellDomain.values.length - 1)];

  /// AppShell owns its own selection and takes only an `initial`, so a
  /// programmatic jump re-keys it.
  // ponytail: re-keying rebuilds the tab stack, so a deep link loses the
  // scroll position of whatever tab was open. Deep links are rare and arrive
  // from outside the app; give AppShell an external controller if that ever
  // stops being true.
  int _rev = 0;

  AppState? _app;

  @override
  void initState() {
    super.initState();
    // A tapped notification asks for a tab via AppState.navRequest. Jump there,
    // then clear the request so it isn't replayed on rebuild.
    _app = context.read<AppState>();
    _app!.navRequest.addListener(_consumeSoon);
    _app!.screenRequest.addListener(_consumeSoon);
    // Cold launch from a tapped notification: the route may already be set
    // before this shell mounted (so the listener never fired). Consume it once
    // attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reaching the shell IS the end of onboarding. Latched here rather than
      // at the pairing screen because an install that upgraded into this build
      // never saw one.
      _markOnboarded();
      _consume();
    });
  }

  bool _pending = false;

  /// Both requests come from ONE tap and are written one after the other, so
  /// whichever listener fires second used to win — and which one that is
  /// inverts between a warm tap (screen, then nav) and a cold launch (the
  /// post-frame callback, in whatever order it reads them). A `/breathing`
  /// notification therefore landed on Wellness or on Home depending on
  /// whether the app happened to be running. Read the pair together, once
  /// both have landed.
  void _consumeSoon() {
    if (_pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      _consume();
    });
  }

  void _consume() {
    final app = _app;
    // Leave the request standing if there is no shell to act on it — the next
    // one consumes it in its post-frame callback rather than finding it eaten.
    if (app == null || !mounted) return;
    final s = app.screenRequest.value;
    final tab = app.navRequest.value;
    app.screenRequest.value = null;
    app.navRequest.value = -1;
    // A screen route carries its own domain; the tab index alongside it is
    // the base the payload was built with, not a second destination.
    if (s != null && s.isNotEmpty) {
      _go(domainForRoute(s));
      final screen = screenForRoute(s);
      if (screen != null) {
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
      }
      return;
    }
    if (tab >= 0) _go(domainForTab(tab));
  }

  void _go(ShellDomain d) {
    if (d == _domain) return;
    setState(() {
      _domain = d;
      _rev++;
    });
    Prefs.setInt(Prefs.shellTab, d.index);
  }

  @override
  void dispose() {
    _app?.navRequest.removeListener(_consumeSoon);
    _app?.screenRequest.removeListener(_consumeSoon);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SELECT, not watch: a bool that flips twice a workout, not the ~1 Hz
    // AppState tick.
    final live = context.select<AppState, bool>((a) => a.activeWorkout != null);
    return AppShell(
      key: ValueKey(_rev),
      initial: _domain,
      banner: live ? const _LiveSessionBar() : null,
      onSelect: (d) {
        _domain = d;
        Prefs.setInt(Prefs.shellTab, d.index);
      },
      builder: (c, d) => switch (d) {
        ShellDomain.home => const HomeScreen(),
        ShellDomain.health => const HealthScreen(),
        ShellDomain.nutrition => const NutritionScreen(),
        ShellDomain.workout => const WorkoutScreen(),
        ShellDomain.wellness => const WellnessScreen(),
      },
    );
  }
}

/// The way back into a session that is running while its screen is not on
/// screen — minimised, or left behind when the app was killed and relaunched.
///
/// Without it, leaving the live screen orphaned the session: `activeWorkout`
/// stayed open, every later workout was refused, and the only control that
/// could end it was the iOS Live Activity's Finish button. Android had
/// nothing at all.
///
/// No clock: the elapsed time would be stale the moment it was painted, and a
/// per-second rebuild of the whole shell to keep one number honest is not a
/// trade worth making. The number is on the screen this taps through to.
class _LiveSessionBar extends StatelessWidget {
  const _LiveSessionBar();

  Future<void> _resume(BuildContext c) async {
    final app = c.read<AppState>();
    final draft = LiveDraft.current;
    final a = draft == null ? null : activityByName(draft.activityKey);
    if (a == null) return;
    final nav = Navigator.of(c);
    // The lifter's previous and best. Absent renders as "First time on this
    // lift", which would be a false claim on a resumed session.
    final history = await loadSetHistory();
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => liveFor(a,
          private: draft!.private,
          weightKg: draft.weightKg,
          host: activityHost(app, history: history)),
    ));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final draft = LiveDraft.current;
    final a = draft == null ? null : activityByName(draft.activityKey);
    // A session the app is holding but this build cannot draw — an older
    // build's, or one rehydrated from a `sessions` row after a crash. Saying
    // nothing beats offering a button that opens the wrong screen.
    if (a == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Pressable(
        semanticLabel: 'Back to your ${a.name.toLowerCase()} session',
        onTap: () => _resume(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration:
                  BoxDecoration(color: p.wash(a.color), borderRadius: R.rSm),
              child: Icon(a.icon, size: 16, color: p.on(a.color)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: F.body.copyWith(
                            color: p.ink, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text('Session running',
                        style: F.over.copyWith(color: p.ink3)),
                  ]),
            ),
            Icon(LucideIcons.chevronUp, size: 20, color: p.ink3),
          ]),
        ),
      ),
    );
  }
}
