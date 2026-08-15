// The router and the onboarding decisions, as pure functions.
//
// Onboarding is the flow a user walks through exactly once, so a bug here is
// a bug nobody reports and everybody hits. Two of the cases below are the
// audit's findings written down as regressions:
//
//   · a profile form that promised optional fields and then refused to
//     continue without them,
//   · a pairing screen with no way out of a refused bond.
//
// The deep-link cases exist because a notification is scheduled days before
// it is tapped: a payload written by an older build must still land somewhere
// deterministic after the five tabs were renamed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/onboarding/profile_setup.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// A viewport tall enough that nothing under test is below the fold. The
/// default 800x600 harness window hides the very buttons these tests are
/// about, which is a property of the harness and not of the screen — the
/// goldens are where layout at a real phone size is checked.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('the onboarding gate', () {
    test('walks welcome → pairing → profile → shell when nothing is skipped',
        () {
      for (final r in AppRoute.values) {
        expect(resolveRoute(r, pairingSkipped: false, profileSeen: false), r);
      }
    });

    test('a skipped pairing still asks for the profile, then opens the app',
        () {
      expect(
        resolveRoute(AppRoute.pairing,
            pairingSkipped: true, profileSeen: false),
        AppRoute.profile,
        reason: 'the four profile numbers are still worth asking for',
      );
      expect(
        resolveRoute(AppRoute.pairing, pairingSkipped: true, profileSeen: true),
        AppRoute.shell,
      );
    });

    test('a deliberately partial profile is not bounced back forever', () {
      // AppState.route keeps returning `profile` while any of age/height/
      // weight/sex is blank. Honouring that literally is the bug: the form
      // says the fields are optional.
      expect(
        resolveRoute(AppRoute.profile,
            pairingSkipped: false, profileSeen: true),
        AppRoute.shell,
      );
    });

    test('loading is never bypassed — there is nothing to show yet', () {
      expect(
        resolveRoute(AppRoute.loading, pairingSkipped: true, profileSeen: true),
        AppRoute.loading,
      );
      // Not even for someone who finished onboarding months ago.
      expect(
        resolveRoute(AppRoute.loading,
            pairingSkipped: false, profileSeen: false, onboarded: true),
        AppRoute.loading,
      );
    });

    test('forgetting a band does not restart onboarding', () {
      // The NAV-03 case: paired for months (so `pairingSkipped` is false),
      // then "Forget this band" → AppState.route goes to `pairing`. That used
      // to drop the user into the first-run pairing screen with every night
      // of their data behind it.
      expect(
        resolveRoute(AppRoute.pairing,
            pairingSkipped: false, profileSeen: true, onboarded: true),
        AppRoute.shell,
      );
      // Same for an install that upgraded into this build and never marked
      // the profile step.
      expect(
        resolveRoute(AppRoute.profile,
            pairingSkipped: false, profileSeen: false, onboarded: true),
        AppRoute.shell,
      );
      // A first run is still a first run.
      expect(
        resolveRoute(AppRoute.pairing,
            pairingSkipped: false, profileSeen: false, onboarded: false),
        AppRoute.pairing,
      );
      expect(
        resolveRoute(AppRoute.welcome,
            pairingSkipped: false, profileSeen: false, onboarded: true),
        AppRoute.welcome,
        reason: 'welcome is reached only with no band AND no choice made',
      );
    });
  });

  group('deep links survive the five-tab rename', () {
    test('every notification tab index resolves', () {
      expect(domainForTab(0), ShellDomain.home);
      // Sleep, Heart and Body all folded into Health.
      expect(domainForTab(1), ShellDomain.health);
      expect(domainForTab(2), ShellDomain.health);
      expect(domainForTab(3), ShellDomain.health);
      expect(domainForTab(4), ShellDomain.workout);
      // A payload from a build that had more tabs than we do.
      expect(domainForTab(9), ShellDomain.home);
      expect(domainForTab(-1), ShellDomain.home);
    });

    test('every kRoute constant lands somewhere deliberate', () {
      const routes = {
        kRouteAiMorning: ShellDomain.home,
        kRouteAiEvening: ShellDomain.home,
        kRouteJournalCompose: ShellDomain.wellness,
        kRouteBreathing: ShellDomain.wellness,
        kRouteWorkoutSuggestion: ShellDomain.workout,
      };
      routes.forEach((route, domain) {
        expect(domainForRoute(route), domain, reason: route);
      });
      // Payload routes that predate the five-tab shell, and that
      // `resolveTapRoute` does not carry yet — the destinations exist here so
      // they stop landing on Home the moment it does.
      expect(domainForRoute('/profile'), ShellDomain.home);
      expect(screenForRoute('/profile'), isA<ProfileHome>(),
          reason: 'the battery notification promises the band, not Home');
      // A week of sleep, strain and recovery is Health. There is no recap
      // screen; landing on Home was not even close.
      expect(domainForRoute('/recap'), ShellDomain.health);
      // Unknown / retired routes must not crash a cold launch.
      expect(domainForRoute(''), ShellDomain.home);
      expect(screenForRoute('/nope'), isNull);
    });

    test('the tab index the shell persists round-trips through the enum', () {
      for (final d in ShellDomain.values) {
        expect(ShellDomain.values[d.index], d);
      }
    });
  });

  group('pairing failures are distinguishable', () {
    test('a dismissed picker is not an error', () {
      expect(classifyPairError(Exception('Pairing cancelled.')),
          PairPhase.cancelled);
    });

    test('a refused bond is its own state, because its fix is elsewhere', () {
      expect(classifyPairError(Exception('createBond refused'),),
          PairPhase.bondRefused);
      // The engine's own counter is enough on its own — the message from a
      // platform channel is not guaranteed to name the bond.
      expect(classifyPairError(Exception('link lost'), bondRefusals: 2),
          PairPhase.bondRefused);
    });

    test('anything else keeps its real message and stays generic', () {
      expect(classifyPairError(Exception('gatt 133')), PairPhase.failed);
    });

    testWidgets('every failure state offers a way into the app anyway',
        (tester) async {
      _tallView(tester);
      for (final phase in PairPhase.values) {
        var skipped = false;
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: PairingView(
              phase: phase, onPair: () {}, onSkip: () => skipped = true),
        ));
        if (phase == PairPhase.paired) continue;
        await tester.tap(find.text('Skip for now'));
        expect(skipped, isTrue, reason: '$phase has no escape');
      }
    });
  });

  group('profile setup keeps its promise', () {
    testWidgets('continue is gated on sex alone, and blanks stay blank',
        (tester) async {
      _tallView(tester);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ProfileSetupView(onSave: (f) async => saved = f),
      ));

      // Nothing chosen: the one required field is missing.
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(saved, isNull);

      await tester.tap(find.text('Female'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!['sex'], 'f');
      // The three optional fields were left blank, so they are ABSENT — not
      // zero, and not a default body.
      expect(saved!.containsKey('age'), isFalse);
      expect(saved!.containsKey('height_cm'), isFalse);
      expect(saved!.containsKey('weight_kg'), isFalse);
    });

    testWidgets('what is typed is what is written', (tester) async {
      _tallView(tester);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ProfileSetupView(onSave: (f) async => saved = f),
      ));
      await tester.tap(find.text('Male'));
      await tester.enterText(find.byType(TextField).at(0), '34');
      await tester.enterText(find.byType(TextField).at(2), '78.4');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(saved!['sex'], 'm');
      expect(saved!['age'], 34);
      expect(saved!['weight_kg'], 78.4);
      expect(saved!.containsKey('height_cm'), isFalse);
    });
  });

  group('the day-0 contract', () {
    test('the unlock date is exactly the nights still owed', () {
      final now = DateTime(2026, 8, 22);
      expect(UnlockContract.unlockDate(now, 3, 14), DateTime(2026, 9, 2));
      // Already unlocked: today, not a date in the past.
      expect(UnlockContract.unlockDate(now, 14, 14), DateTime(2026, 8, 22));
      expect(UnlockContract.unlockDate(now, 20, 14), DateTime(2026, 8, 22));
    });

    test('the date reads as a date a person can hold', () {
      expect(formatDay(DateTime(2026, 9, 3)), 'Thu 3 Sep');
      expect(formatDay(DateTime(2026, 1, 1)), 'Thu 1 Jan');
    });

    testWidgets('it locks the headline and shows live HR instead',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: UnlockContract(
              metric: 'Readiness',
              have: 3,
              need: 14,
              liveHr: 61,
              now: DateTime(2026, 8, 22)),
        ),
      ));
      expect(find.text('Opens Wed 2 Sep'), findsOneWidget);
      expect(find.text('3 of 14 nights banked'), findsOneWidget);
      expect(find.text('61'), findsOneWidget);
      // Never a number standing in for the locked metric.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('with no band streaming it says so rather than showing 0',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: UnlockContract(
              metric: 'Readiness', have: 0, need: 14, now: DateTime(2026, 8, 22)),
        ),
      ));
      expect(find.text('Band not streaming'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('sources rank by quality, not by who wrote last', () {
    HealthSource src(String name, SourceTier tier, {DateTime? at}) =>
        HealthSource(
            name: name, kind: '', tier: tier, icon: LucideIcons.watch,
            lastData: at);

    test('a fresher worse sensor never outranks a better one', () {
      final ranked = rankSources([
        src('Phone', SourceTier.phone, at: DateTime(2026, 8, 22, 12)),
        src('Band', SourceTier.wristOptical, at: DateTime(2026, 8, 20)),
        src('Chest strap', SourceTier.beatToBeat, at: DateTime(2026, 8, 1)),
      ]);
      expect(ranked.map((s) => s.name).toList(),
          ['Chest strap', 'Band', 'Phone']);
    });

    test('recency only breaks a tie inside a tier', () {
      final ranked = rankSources([
        src('Old band', SourceTier.wristOptical, at: DateTime(2026, 8, 1)),
        src('New band', SourceTier.wristOptical, at: DateTime(2026, 8, 22)),
      ]);
      expect(ranked.first.name, 'New band');
    });

    test('a user preference is the last word, not the first', () {
      final ranked = rankSources([
        src('B', SourceTier.wristOptical),
        src('A', SourceTier.wristOptical),
      ], preferred: ['B']);
      expect(ranked.first.name, 'B');
    });
  });

  test('byte sizes read like sizes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
  });
}
